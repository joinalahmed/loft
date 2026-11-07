import Foundation
import Combine

/// A real interactive zsh behind a pseudo-terminal (via /usr/bin/script, which sets up the
/// controlling tty so ⌃C and job control work), with escape sequences stripped for a clean,
/// readable transcript in the notch. Lines are capped so long sessions stay cheap.
@MainActor
final class TerminalSession: ObservableObject {
    static let shared = TerminalSession()
    @Published private(set) var lines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var history: [String] = UserDefaults.standard.stringArray(forKey: "terminalHistory") ?? []
    private var process: Process?
    private var input: FileHandle?
    private var partial = ""
    private var pendingCR = false
    private let maxLines = 2000
    private static let csi = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?<=>]*[ -/]*[@-~]|\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)|\u{1B}[()#%][0-9A-Za-z]|\u{1B}[=>7-8NOM]|[\u{0E}\u{0F}\u{07}]")
    private init() {}

    func startIfNeeded() {
        guard process == nil else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        p.arguments = ["-q", "/dev/null", "/bin/zsh", "-il"]
        var env = ProcessInfo.processInfo.environment
        env["ZDOTDIR"] = Self.rcDirectory().path       // user's rc files + a plain prompt
        env["TERM"] = "dumb"; env["COLUMNS"] = "110"; env["LINES"] = "14"
        env["PAGER"] = "cat"; env["GIT_PAGER"] = "cat"; env["CLICOLOR"] = "0"; env["NO_COLOR"] = "1"
        env["LOFT_TERMINAL"] = "1"
        p.environment = env
        p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = outPipe
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return }
            Task { @MainActor in self?.append(text) }
        }
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isRunning = false; self.process = nil; self.input = nil
                self.append("\n[session ended · press ↩ to start a new shell]\n")
            }
        }
        do {
            try p.run()
            process = p; input = inPipe.fileHandleForWriting; isRunning = true
        } catch {
            append("Could not start shell: \(error.localizedDescription)\n")
        }
    }

    func send(_ line: String) {
        startIfNeeded()
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            history.removeAll { $0 == trimmed }
            history.append(trimmed)
            if history.count > 200 { history.removeFirst(history.count - 200) }
            UserDefaults.standard.set(history, forKey: "terminalHistory")
        }
        if trimmed == "clear" { clear(); input?.write("\n".data(using: .utf8)!); return }
        input?.write((line + "\n").data(using: .utf8)!)
    }

    func interrupt() { input?.write(Data([0x03])) }     // ⌃C
    func eof() { input?.write(Data([0x04])) }           // ⌃D

    func clear() { lines.removeAll(); partial = "" }

    func restart() {
        process?.terminate(); process = nil; input = nil; isRunning = false
        clear(); startIfNeeded()
    }

    /// A ZDOTDIR that loads the user's own zsh files, then swaps in a plain prompt: powerline
    /// segments and Nerd Font glyphs from themes like Powerlevel10k do not survive a text transcript.
    nonisolated private static func rcDirectory() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Loft/zsh")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // zsh re-reads ZDOTDIR before each startup file, so it must stay ours until .zshrc is done.
        let zshenv = """
        __loft_zdotdir=$ZDOTDIR
        [[ -r $HOME/.zshenv ]] && source $HOME/.zshenv
        ZDOTDIR=$__loft_zdotdir
        """
        let zshrc = """
        export LOFT_TERMINAL=1
        typeset -g POWERLEVEL9K_INSTANT_PROMPT=off
        [[ -r $HOME/.zprofile ]] && source $HOME/.zprofile
        [[ -r $HOME/.zshrc ]] && source $HOME/.zshrc
        # Loft terminal: plain prompt, no right prompt, no prompt-theme hooks (segments do not render in a transcript).
        precmd_functions=() preexec_functions=()
        unset RPROMPT RPS1 RPROMPT2
        PROMPT=$'%1~ ❯ '
        setopt NO_PROMPT_SP NO_BEEP
        ZDOTDIR=$HOME
        printf '\\e]loft-clear\\a'
        """
        for (name, body) in [(".zshenv", zshenv), (".zshrc", zshrc)] {
            let url = dir.appendingPathComponent(name)
            if (try? String(contentsOf: url, encoding: .utf8)) != body { try? body.write(to: url, atomically: true, encoding: .utf8) }
        }
        return dir
    }

    // MARK: Transcript

    private func append(_ raw: String) {
        var raw = raw
        if let r = raw.range(of: "\u{1B}]loft-clear\u{07}") {      // emitted by our .zshrc once startup noise is over
            lines.removeAll(); partial = ""; raw = String(raw[r.upperBound...])
        }
        let ns = raw as NSString
        var text = Self.csi.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        for ch in text {
            switch ch {
            case "\n":
                lines.append(partial); partial = ""; pendingCR = false
            case "\r":
                pendingCR = true                       // progress bars: next text overwrites the line
            case "\u{08}":
                if !partial.isEmpty { partial.removeLast() }
            case "\t":
                partial += "    "
            default:
                if pendingCR { partial = ""; pendingCR = false }
                if ch.isASCII && ch.asciiValue! < 0x20 { continue }
                partial.append(ch)
            }
        }
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
    }

    var transcript: [String] { partial.isEmpty ? lines : lines + [partial] }
    var promptLine: String { partial }
}
