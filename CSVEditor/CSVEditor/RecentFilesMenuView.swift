import SwiftUI

struct RecentFilesMenuView: View {
    @StateObject private var manager = RecentFilesManager()

    var body: some View {
        ForEach(manager.recentFiles, id: \.self) { url in
            Button(url.lastPathComponent) {
                NotificationCenter.default.post(
                    name: .openRecentFile,
                    object: nil,
                    userInfo: ["url": url]
                )
            }
        }

        if !manager.recentFiles.isEmpty {
            Divider()

            Button("Clear Menu") {
                manager.clearRecentFiles()
            }
        }
    }
}
