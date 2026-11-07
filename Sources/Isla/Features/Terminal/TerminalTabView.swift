import SwiftUI

struct TerminalTabView: View {
    /// Powerlevel10k / Starship prompts use Nerd Font glyphs; prefer an installed patched font.
    static let monoFont: Font = {
        for name in ["MesloLGS NF", "JetBrainsMono Nerd Font", "FiraCode Nerd Font", "Hack Nerd Font", "MesloLGM Nerd Font"] where NSFont(name: name, size: 11) != nil {
            return .custom(name, size: 11)
        }
        return .system(size: 11, design: .monospaced)
    }()
    @ObservedObject var term = TerminalSession.shared
    @ObservedObject var vm = NotchViewModel.shared
    @Environment(\.islandTint) private var tint
    @State private var draft = ""
    @State private var historyIndex: Int? = nil
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(term.transcript.enumerated()), id: \.offset) { i, line in
                            Text(line.isEmpty ? " " : line)
                                .font(Self.monoFont)
                                .foregroundStyle(i == term.transcript.count - 1 ? .white : .white.opacity(0.78))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                }
                .scrollIndicators(.never)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
                .onChange(of: term.transcript.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            HStack(spacing: 8) {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
                TextField("Type a command and press ↩", text: $draft)
                    .textFieldStyle(.plain).font(Self.monoFont)
                    .focused($focused)
                    .onSubmit { submit() }
                    .onKeyPress(.upArrow) { recall(-1); return .handled }
                    .onKeyPress(.downArrow) { recall(1); return .handled }
                    .onKeyPress(characters: .init(charactersIn: "c"), phases: .down) { press in
                        guard press.modifiers.contains(.control) else { return .ignored }
                        term.interrupt(); return .handled
                    }
                    .onKeyPress(characters: .init(charactersIn: "d"), phases: .down) { press in
                        guard press.modifiers.contains(.control), draft.isEmpty else { return .ignored }
                        term.eof(); return .handled
                    }
                    .onKeyPress(characters: .init(charactersIn: "l"), phases: .down) { press in
                        guard press.modifiers.contains(.control) else { return .ignored }
                        term.clear(); return .handled
                    }
                SmallIconButton(symbol: "xmark.octagon", size: 11, help: "Interrupt (⌃C)", tint: .orange) { term.interrupt() }
                SmallIconButton(symbol: "trash", size: 11, help: "Clear (⌃L)") { term.clear() }
                SmallIconButton(symbol: "arrow.counterclockwise", size: 11, help: "Restart shell") { term.restart() }
                Circle().fill(term.isRunning ? Color.green : Color.red).frame(width: 6, height: 6).help(term.isRunning ? "zsh running" : "no shell")
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(.white.opacity(0.08), in: Capsule())
        }
        .onAppear {
            term.startIfNeeded()
            focused = vm.wantsKeyboard
        }
        .onReceive(NotificationCenter.default.publisher(for: .islaWantsKeyboard)) { _ in focused = true }
    }

    private func submit() {
        term.send(draft)
        draft = ""; historyIndex = nil
    }

    private func recall(_ delta: Int) {
        let h = term.history
        guard !h.isEmpty else { return }
        var i = historyIndex ?? h.count
        i = max(0, min(h.count, i + delta))
        historyIndex = i
        draft = i == h.count ? "" : h[i]
    }
}
