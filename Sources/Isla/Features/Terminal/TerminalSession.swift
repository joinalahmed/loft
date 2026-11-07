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
        env["TERM"] = "dumb"; env["COLUMNS"] = "110"; env["LINES"] = "14"
        env["PAGER"] = "cat"; env["GIT_PAGER"] = "cat"; env["CLICOLOR"] = "0"; env["NO_COLOR"] = "1"
        env["ISLA_TERMINAL"] = "1"
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

    // MARK: Transcript

    private func append(_ raw: String) {
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
