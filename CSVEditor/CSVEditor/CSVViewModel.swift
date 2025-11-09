import SwiftUI
import AppKit

class CSVViewModel: ObservableObject {
    @Published var data: [[String]] = []
    @Published var isModified = false
    @Published var currentFileURL: URL?
    @Published var shouldFocusFirstCell = false

    private var delimiter: String = ","
    private var savedState: [[String]] = []

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText]

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadFile(url: url)
        }
    }

    func loadFile(url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)

            // Detect delimiter
            let firstLine = content.components(separatedBy: .newlines).first ?? ""
            if firstLine.contains("\t") {
                delimiter = "\t"
            } else {
                delimiter = ","
            }

            // Parse CSV/TSV
            data = parseCSV(content: content, delimiter: delimiter)
            savedState = data.map { $0.map { $0 } } // Deep copy
            currentFileURL = url
            isModified = false
            shouldFocusFirstCell = true

            // Notify that a file was loaded
            NotificationCenter.default.post(
                name: .fileLoaded,
                object: nil,
                userInfo: ["url": url]
            )
        } catch {
            print("Error loading file: \(error)")
            showAlert(message: "Failed to load file: \(error.localizedDescription)")
        }
    }

    func reloadFile() {
        guard let url = currentFileURL else { return }

        // Notify GridHostView to save state before reloading
        NotificationCenter.default.post(name: .saveStateBeforeReload, object: nil)

        loadFile(url: url)
    }

    private func parseCSV(content: String, delimiter: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        for char in content {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == Character(delimiter) && !inQuotes {
                currentRow.append(currentField)
                currentField = ""
            } else if char == "\n" && !inQuotes {
                currentRow.append(currentField)
                if !currentRow.isEmpty || !currentField.isEmpty {
                    rows.append(currentRow)
                }
                currentRow = []
                currentField = ""
            } else if char == "\r" && !inQuotes {
                // Skip carriage return
                continue
            } else {
                currentField.append(char)
            }
        }

        // Add last field and row if not empty
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        // Normalize row lengths
        if let maxColumns = rows.map({ $0.count }).max() {
            for i in 0..<rows.count {
                while rows[i].count < maxColumns {
                    rows[i].append("")
                }
            }
        }

        return rows
    }

    func saveFile() {
        guard let url = currentFileURL else { return }
        saveToURL(url)
    }

    func saveFileAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText]
        panel.nameFieldStringValue = currentFileURL?.lastPathComponent ?? "untitled.csv"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.saveToURL(url)
            self?.currentFileURL = url
        }
    }

    private func saveToURL(_ url: URL) {
        do {
            // Determine delimiter from file extension
            let ext = url.pathExtension.lowercased()
            let saveDelimiter = (ext == "tsv" || ext == "tab") ? "\t" : ","

            var content = ""
            for row in data {
                let escapedRow = row.map { field -> String in
                    // Escape fields containing delimiter, quotes, or newlines
                    if field.contains(saveDelimiter) || field.contains("\"") || field.contains("\n") {
                        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
                    }
                    return field
                }
                content += escapedRow.joined(separator: saveDelimiter) + "\n"
            }

            try content.write(to: url, atomically: true, encoding: .utf8)
            savedState = data.map { $0.map { $0 } } // Deep copy
            isModified = false
            delimiter = saveDelimiter
        } catch {
            print("Error saving file: \(error)")
            showAlert(message: "Failed to save file: \(error.localizedDescription)")
        }
    }

    func updateModifiedState() {
        isModified = (data != savedState)
    }

    private func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
