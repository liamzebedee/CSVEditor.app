import SwiftUI

@main
struct CSVEditorApp: App {
    @StateObject private var appState = AppState()

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
}
