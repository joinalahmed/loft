import SwiftUI
import Combine

@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()
    @Published var text: String { didSet { scheduleSave() } }
    private let file = AppSupport.directory("").appendingPathComponent("notes.md")
    private var saveTask: Task<Void, Never>?
    private init() { text = (try? String(contentsOf: file, encoding: .utf8)) ?? "" }
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [text, file] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
    }
}

struct NotesTabView: View {
    @ObservedObject var notes = NotesStore.shared
    @FocusState private var focused: Bool
    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $notes.text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .focused($focused)
            if notes.text.isEmpty {
                Text("Quick note… saved automatically").font(.system(size: 13)).foregroundStyle(.tertiary).padding(12).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 4) {
                Text("\(notes.text.split(whereSeparator: \.isWhitespace).count) words").font(.system(size: 9)).foregroundStyle(.tertiary)
                SmallIconButton(symbol: "doc.on.doc", size: 10, help: "Copy note") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(notes.text, forType: .string)
                }
                SmallIconButton(symbol: "trash", size: 10, help: "Clear") { notes.text = "" }
            }.padding(6)
        }
        .onAppear { if NotchViewModel.shared.wantsKeyboard { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true } } }
        .onReceive(NotificationCenter.default.publisher(for: .islaWantsKeyboard)) { _ in focused = true }
    }
}
