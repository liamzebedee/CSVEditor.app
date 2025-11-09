import SwiftUI

@main
struct CSVEditorApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(initialFileURL: appState.initialFileURL)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    NotificationCenter.default.post(name: .openFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    RecentFilesMenuView()
                }

                Divider()

                Button("Reload") {
                    NotificationCenter.default.post(name: .reloadFile, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Save") {
                    NotificationCenter.default.post(name: .saveFile, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As...") {
                    NotificationCenter.default.post(name: .saveFileAs, object: nil)
                }
                .keyboardShortcut("S", modifiers: .command)
            }
        }
    }

    init() {
        // Check for command-line arguments
        let args = CommandLine.arguments
        if args.count > 1 {
            let filePath = args[1]
            let fileURL = URL(fileURLWithPath: filePath)
            _appState = StateObject(wrappedValue: AppState(initialFileURL: fileURL))
        } else {
            _appState = StateObject(wrappedValue: AppState())
        }
    }
}

class AppState: ObservableObject {
    let initialFileURL: URL?

    init(initialFileURL: URL? = nil) {
        self.initialFileURL = initialFileURL
    }
}

extension Notification.Name {
    static let openFile = Notification.Name("openFile")
    static let saveStateBeforeReload = Notification.Name("saveStateBeforeReload")
    static let openRecentFile = Notification.Name("openRecentFile")
    static let reloadFile = Notification.Name("reloadFile")
    static let saveFile = Notification.Name("saveFile")
    static let saveFileAs = Notification.Name("saveFileAs")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var recentFilesManager = RecentFilesManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Listen for file loads to update recent files
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFileLoaded),
            name: .fileLoaded,
            object: nil
        )
    }

    @objc func handleFileLoaded(_ notification: Notification) {
        if let url = notification.userInfo?["url"] as? URL {
            recentFilesManager.addRecentFile(url)
        }
    }
}

class RecentFilesManager: ObservableObject {
    private let recentFilesKey = "RecentFiles"
    private let maxRecentFiles = 10
    @Published var recentFiles: [URL] = []

    init() {
        loadRecentFiles()
    }

    func addRecentFile(_ url: URL) {
        // Remove if already exists
        recentFiles.removeAll { $0 == url }

        // Add to front
        recentFiles.insert(url, at: 0)

        // Limit to max
        if recentFiles.count > maxRecentFiles {
            recentFiles = Array(recentFiles.prefix(maxRecentFiles))
        }

        saveRecentFiles()
    }

    func clearRecentFiles() {
        recentFiles = []
        saveRecentFiles()
    }

    private func loadRecentFiles() {
        if let data = UserDefaults.standard.data(forKey: recentFilesKey),
           let urls = try? JSONDecoder().decode([URL].self, from: data) {
            recentFiles = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    private func saveRecentFiles() {
        if let data = try? JSONEncoder().encode(recentFiles) {
            UserDefaults.standard.set(data, forKey: recentFilesKey)
        }
    }
}

extension Notification.Name {
    static let fileLoaded = Notification.Name("fileLoaded")
}
