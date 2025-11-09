import SwiftUI
import AppKit

struct ContentView: NSViewControllerRepresentable {
    let initialFileURL: URL?

    func makeNSViewController(context: Context) -> TableViewController {
        let controller = TableViewController()
        controller.initialFileURL = initialFileURL
        return controller
    }

    func updateNSViewController(_ nsViewController: TableViewController, context: Context) {
    }
}

class TableViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var viewModel = CSVViewModel()
    var tableView: NSTableView!
    var scrollView: NSScrollView!
    var initialFileURL: URL?
    var undoStack: [(row: Int, col: Int, oldValue: String, newValue: String)] = []
    var selectedRow: Int = 0
    var selectedColumn: Int = 0

    override func loadView() {
        view = NSView()
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)

        // Create toolbar
        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        let openButton = NSButton(title: "Open File", target: self, action: #selector(openFile))
        openButton.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(openButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveFile))
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(saveButton)

        let saveAsButton = NSButton(title: "Save As...", target: self, action: #selector(saveFileAs))
        saveAsButton.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(saveAsButton)

        // Create table view
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsColumnResizing = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnSelection = true
        tableView.allowsMultipleSelection = false

        scrollView.documentView = tableView
        view.addSubview(scrollView)

        // Layout
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 50),

            openButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 10),
            openButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            saveButton.trailingAnchor.constraint(equalTo: saveAsButton.leadingAnchor, constant: -10),
            saveButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            saveAsButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -10),
            saveAsButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let url = initialFileURL {
            viewModel.loadFile(url: url)
            reloadTable()
        }

        // Add keyboard handlers
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Cmd+S to save
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "s" {
                self.saveFile()
                return nil
            }

            // Cmd+Z to undo
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
                self.performUndo()
                return nil
            }

            // Arrow key navigation
            if event.keyCode == 126 { // Up arrow
                self.moveSelection(rowDelta: -1, colDelta: 0)
                return nil
            } else if event.keyCode == 125 { // Down arrow
                self.moveSelection(rowDelta: 1, colDelta: 0)
                return nil
            } else if event.keyCode == 123 { // Left arrow
                self.moveSelection(rowDelta: 0, colDelta: -1)
                return nil
            } else if event.keyCode == 124 { // Right arrow
                self.moveSelection(rowDelta: 0, colDelta: 1)
                return nil
            } else if event.keyCode == 36 || event.keyCode == 76 { // Enter or Return
                self.startEditingCurrentCell()
                return nil
            }

            return event
        }
    }

    func reloadTable() {
        while tableView.tableColumns.count > 0 {
            tableView.removeTableColumn(tableView.tableColumns[0])
        }

        guard let firstRow = viewModel.data.first else { return }

        for i in 0..<firstRow.count {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col\(i)"))
            column.title = columnLabel(i)
            column.width = 150
            tableView.addTableColumn(column)
        }

        tableView.reloadData()
    }

    private func columnLabel(_ index: Int) -> String {
        var label = ""
        var num = index
        repeat {
            label = String(UnicodeScalar(65 + (num % 26))!) + label
            num = num / 26 - 1
        } while num >= 0
        return label
    }

    @objc func openFile() {
        viewModel.openFile()
        reloadTable()
    }

    @objc func saveFile() {
        viewModel.saveFile()
    }

    @objc func saveFileAs() {
        viewModel.saveFileAs()
    }

    func moveSelection(rowDelta: Int, colDelta: Int) {
        let newRow = max(0, min(viewModel.data.count - 1, selectedRow + rowDelta))
        let newCol = max(0, min((viewModel.data.first?.count ?? 0) - 1, selectedColumn + colDelta))

        selectedRow = newRow
        selectedColumn = newCol

        tableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        tableView.selectColumnIndexes(IndexSet(integer: newCol), byExtendingSelection: false)
        tableView.scrollRowToVisible(newRow)
        tableView.scrollColumnToVisible(newCol)
    }

    func startEditingCurrentCell() {
        guard selectedRow < viewModel.data.count,
              selectedColumn < (viewModel.data.first?.count ?? 0) else { return }

        tableView.editColumn(selectedColumn, row: selectedRow, with: nil, select: true)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return viewModel.data.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn = tableColumn,
              let columnIndex = tableView.tableColumns.firstIndex(of: tableColumn) else {
            return nil
        }

        let identifier = NSUserInterfaceItemIdentifier("Cell")
        var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView

        if cell == nil {
            cell = NSTableCellView()
            cell?.identifier = identifier

            let textField = NSTextField()
            textField.isBordered = false
            textField.backgroundColor = .clear
            textField.isEditable = true
            textField.isSelectable = true
            textField.drawsBackground = false
            textField.translatesAutoresizingMaskIntoConstraints = false

            cell?.addSubview(textField)
            cell?.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 2),
                textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -2),
                textField.topAnchor.constraint(equalTo: cell!.topAnchor, constant: 2),
                textField.bottomAnchor.constraint(equalTo: cell!.bottomAnchor, constant: -2)
            ])
        }

        cell?.textField?.stringValue = viewModel.data[row][columnIndex]
        cell?.textField?.delegate = self
        cell?.textField?.tag = row * 1000 + columnIndex

        return cell
    }
}

extension TableViewController: NSTextFieldDelegate {
    func controlTextDidBeginEditing(_ obj: Notification) {
        if let textField = obj.object as? NSTextField {
            let row = textField.tag / 1000
            let col = textField.tag % 1000
            // Store original value when editing begins
            textField.placeholderString = viewModel.data[row][col]
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if let textField = obj.object as? NSTextField {
            let row = textField.tag / 1000
            let col = textField.tag % 1000
            let oldValue = textField.placeholderString ?? viewModel.data[row][col]
            let newValue = textField.stringValue

            if oldValue != newValue {
                // Add to undo stack
                undoStack.append((row: row, col: col, oldValue: oldValue, newValue: newValue))
                viewModel.data[row][col] = newValue
                viewModel.isModified = true
            }
        }
    }

    func performUndo() {
        guard let lastEdit = undoStack.popLast() else { return }

        viewModel.data[lastEdit.row][lastEdit.col] = lastEdit.oldValue
        viewModel.isModified = true
        tableView.reloadData()
    }
}
