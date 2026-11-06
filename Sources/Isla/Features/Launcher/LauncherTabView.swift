import SwiftUI
import AppKit

/// App launcher: running apps first (click to switch, right-click to quit), then favourites
/// from /Applications. Type to filter.
struct LauncherTabView: View {
    @State private var query = ""
    @State private var apps: [LauncherApp] = []
    @State private var running: [NSRunningApplication] = []
    @ObservedObject var vm = NotchViewModel.shared
    @FocusState private var focused: Bool

    private var filtered: [LauncherApp] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        return apps.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Launch…", text: $query).textFieldStyle(.plain).font(.system(size: 12)).focused($focused)
                    .onSubmit { if let a = filtered.first { launch(a) } }
            }
            .padding(.horizontal, 10).frame(height: 26).background(.white.opacity(0.08), in: Capsule())
            if query.isEmpty, !running.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(running, id: \.processIdentifier) { app in
                            Button { app.activate(); vm.close() } label: {
                                VStack(spacing: 2) {
                                    Image(nsImage: app.icon ?? NSImage()).resizable().frame(width: 28, height: 28)
                                    Text(app.localizedName ?? "").font(.system(size: 9)).lineLimit(1).frame(width: 52)
                                }.padding(4)
                            }.buttonStyle(.plain)
                            .contextMenu {
                                Button("Quit") { app.terminate() }
                                Button("Hide") { app.hide() }
                                Button("Force Quit") { app.forceTerminate() }
                            }
                        }
                    }
                }.scrollIndicators(.never).frame(height: 50)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                    ForEach(filtered) { app in
                        Button { launch(app) } label: {
                            VStack(spacing: 2) {
                                Image(nsImage: app.icon).resizable().frame(width: 30, height: 30)
                                Text(app.name).font(.system(size: 9)).lineLimit(1)
                            }.frame(maxWidth: .infinity).padding(.vertical, 4)
                        }.buttonStyle(.plain)
                    }
                }
            }.scrollIndicators(.never)
        }
        .onAppear {
            focused = vm.wantsKeyboard
            running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0 != .current }
            if apps.isEmpty { Task.detached { let list = LauncherApp.scan(); await MainActor.run { apps = list } } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .islaWantsKeyboard)) { _ in focused = true }
    }

    private func launch(_ app: LauncherApp) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        vm.close(); query = ""
    }
}

struct LauncherApp: Identifiable, Equatable {
    let url: URL
    let name: String
    let icon: NSImage
    var id: URL { url }

    nonisolated static func scan() -> [LauncherApp] {
        let fm = FileManager.default
        var dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities"]
        dirs.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path)
        var out: [LauncherApp] = []
        for dir in dirs {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for n in names where n.hasSuffix(".app") {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(n)
                let name = (fm.displayName(atPath: url.path) as NSString).deletingPathExtension
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 30, height: 30)
                out.append(LauncherApp(url: url, name: name, icon: icon))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
