import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = CSVViewModel()
    let initialFileURL: URL?

    private var windowTitle: String {
        if let url = viewModel.currentFileURL {
            let fileName = url.lastPathComponent
            return viewModel.isModified ? "\(fileName) [Modified]" : fileName
        }
        return "CSV Editor"
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.data.isEmpty {
                VStack {
                    Spacer()
                    Text("No file loaded")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                GridView(viewModel: viewModel)
            }
        }
        .navigationTitle(windowTitle)
        .onAppear {
            if let url = initialFileURL {
                viewModel.loadFile(url: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFile)) { _ in
            viewModel.openFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRecentFile)) { notification in
            if let userInfo = notification.userInfo,
               let url = userInfo["url"] as? URL {
                viewModel.loadFile(url: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reloadFile)) { _ in
            viewModel.reloadFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveFile)) { _ in
            viewModel.saveFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveFileAs)) { _ in
            viewModel.saveFileAs()
        }
    }
}

struct GridView: NSViewRepresentable {
    @ObservedObject var viewModel: CSVViewModel

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder

        let gridView = GridHostView()
        gridView.viewModel = viewModel

        scrollView.documentView = gridView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let gridView = nsView.documentView as? GridHostView else { return }
        gridView.viewModel = viewModel
        if !viewModel.data.isEmpty {
            let shouldFocus = viewModel.shouldFocusFirstCell
            if shouldFocus {
                viewModel.shouldFocusFirstCell = false
            }
            gridView.reloadData(focusOnFirstCell: shouldFocus)
        }
    }
}

class GridHostView: NSView {
    weak var viewModel: CSVViewModel?
    var cells: [[CellTextField]] = []
    var selectedRow: Int = 0
    var selectedCol: Int = 0
    var undoStack: [(row: Int, col: Int, oldValue: String)] = []
    var reloadUndoStack: [[[String]]] = []

    // Use flipped coordinates so (0,0) is top-left
    override var isFlipped: Bool { return true }

    // Enable standard editing commands
    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        if sendType == .string || returnType == .string {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        // Listen for reload notifications
        NotificationCenter.default.addObserver(self, selector: #selector(handleSaveStateBeforeReload), name: .saveStateBeforeReload, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func handleSaveStateBeforeReload() {
        saveStateForReload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { return true }

    override func keyDown(with event: NSEvent) {
        // Handle command key shortcuts
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "o", "r", "s":
                // Pass these through to SwiftUI buttons by calling super
                super.keyDown(with: event)
                return
            case "z":
                performUndo()
                return
            case "c":
                copy(nil)
                return
            case "x":
                cut(nil)
                return
            case "v":
                paste(nil)
                return
            case "a":
                // Cmd+A in grid context - could select all, but we'll skip for now
                return
            default:
                break
            }
        }

        switch event.keyCode {
        case 126: // Up
            moveSelection(rowDelta: -1, colDelta: 0)
        case 125: // Down
            moveSelection(rowDelta: 1, colDelta: 0)
        case 123: // Left
            moveSelection(rowDelta: 0, colDelta: -1)
        case 124: // Right
            moveSelection(rowDelta: 0, colDelta: 1)
        case 36, 76: // Enter/Return
            startEditing()
        case 48: // Tab
            if event.modifierFlags.contains(.shift) {
                moveSelection(rowDelta: 0, colDelta: -1)
            } else {
                moveSelection(rowDelta: 0, colDelta: 1)
            }
        case 51: // Delete/Backspace
            // Delete starts editing with empty content
            startEditingWithText("")
        default:
            // Don't start editing if any modifier keys are pressed (except Shift)
            let hasModifiers = event.modifierFlags.contains(.command) ||
                              event.modifierFlags.contains(.control) ||
                              event.modifierFlags.contains(.option)

            if !hasModifiers {
                // Check if this is a printable character
                if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                    let char = chars.first!
                    // Start editing if it's a printable character (not a control character)
                    if char.isLetter || char.isNumber || char.isPunctuation || char.isSymbol || char == " " {
                        startEditingWithText(String(char))
                        return
                    }
                }
            }
            super.keyDown(with: event)
        }
    }

    func reloadData(focusOnFirstCell: Bool = false) {
        guard let viewModel = viewModel else { return }

        // Remove old cells
        cells.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        cells = []
        subviews.forEach { $0.removeFromSuperview() }

        let data = viewModel.data
        guard !data.isEmpty, let firstRow = data.first else { return }

        let cellHeight: CGFloat = 25
        let headerHeight: CGFloat = 25
        let minCellWidth: CGFloat = 100
        let cellPadding: CGFloat = 20

        // Calculate column widths based on content
        var columnWidths: [CGFloat] = []
        for col in 0..<firstRow.count {
            var maxWidth: CGFloat = minCellWidth

            // Check header width
            let headerText = columnLabel(col)
            let headerSize = (headerText as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])
            maxWidth = max(maxWidth, headerSize.width + cellPadding)

            // Check all cell widths in this column
            for row in 0..<data.count {
                if col < data[row].count {
                    let cellText = data[row][col]
                    let textSize = (cellText as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])
                    maxWidth = max(maxWidth, textSize.width + cellPadding)
                }
            }

            columnWidths.append(maxWidth)
        }

        // Calculate total size needed for scrolling
        let totalWidth = columnWidths.reduce(0, +)
        let totalHeight = headerHeight + CGFloat(data.count) * cellHeight

        // Set frame to accommodate all content
        self.frame = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)

        // Create headers (at top since we're using flipped coordinates)
        var xOffset: CGFloat = 0
        for col in 0..<firstRow.count {
            let label = NSTextField(labelWithString: columnLabel(col))
            label.frame = NSRect(x: xOffset, y: 0, width: columnWidths[col], height: headerHeight)
            label.alignment = .center
            label.backgroundColor = NSColor.controlBackgroundColor
            label.isBordered = true
            addSubview(label)
            xOffset += columnWidths[col]
        }

        // Create cells (starting from headerHeight down)
        for row in 0..<data.count {
            var rowCells: [CellTextField] = []
            xOffset = 0
            for col in 0..<data[row].count {
                let cell = CellTextField()
                cell.frame = NSRect(x: xOffset, y: headerHeight + CGFloat(row) * cellHeight, width: columnWidths[col], height: cellHeight)
                cell.stringValue = data[row][col]
                cell.isBordered = true
                cell.isEditable = false
                cell.isSelectable = false
                cell.drawsBackground = true
                cell.backgroundColor = .white
                cell.row = row
                cell.col = col
                cell.gridView = self

                let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(cellClicked(_:)))
                cell.addGestureRecognizer(clickRecognizer)

                addSubview(cell)
                rowCells.append(cell)
                xOffset += columnWidths[col]
            }
            cells.append(rowCells)
        }

        if focusOnFirstCell {
            selectedRow = 0
            selectedCol = 0
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.updateSelection()
                self.window?.makeFirstResponder(self)
            }
        } else {
            updateSelection()
        }
    }

    @objc func cellClicked(_ recognizer: NSClickGestureRecognizer) {
        if let cell = recognizer.view as? CellTextField {
            selectedRow = cell.row
            selectedCol = cell.col
            updateSelection()
            window?.makeFirstResponder(self)
        }
    }

    func startEditing() {
        guard selectedRow < cells.count, selectedCol < cells[selectedRow].count else { return }
        let cell = cells[selectedRow][selectedCol]

        cell.originalValue = cell.stringValue
        undoStack.append((row: selectedRow, col: selectedCol, oldValue: cell.stringValue))

        cell.isEditable = true
        cell.isSelectable = true
        window?.makeFirstResponder(cell)
        cell.currentEditor()?.selectAll(nil)
    }

    func startEditingWithText(_ text: String) {
        guard selectedRow < cells.count, selectedCol < cells[selectedRow].count else { return }
        let cell = cells[selectedRow][selectedCol]

        cell.originalValue = cell.stringValue
        undoStack.append((row: selectedRow, col: selectedCol, oldValue: cell.stringValue))

        cell.stringValue = text
        cell.isEditable = true
        cell.isSelectable = true
        window?.makeFirstResponder(cell)

        // Move cursor to end of text
        if let editor = cell.currentEditor() as? NSTextView {
            editor.moveToEndOfDocument(nil)
        }
    }

    func cancelEditing(_ cell: CellTextField) {
        // Remove the undo entry since we're cancelling
        if let lastUndo = undoStack.last,
           lastUndo.row == cell.row && lastUndo.col == cell.col {
            undoStack.removeLast()
        }

        cell.isEditable = false
        cell.isSelectable = false

        // Update selection to the edited cell
        selectedRow = cell.row
        selectedCol = cell.col

        // Restore focus to grid view
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateSelection()
            self.window?.makeFirstResponder(self)
        }
    }

    func moveSelection(rowDelta: Int, colDelta: Int) {
        guard let viewModel = viewModel else { return }

        let newRow = max(0, min(viewModel.data.count - 1, selectedRow + rowDelta))
        let newCol = max(0, min((viewModel.data.first?.count ?? 0) - 1, selectedCol + colDelta))

        selectedRow = newRow
        selectedCol = newCol
        updateSelection()
        scrollToSelectedCell()
        window?.makeFirstResponder(self)
    }

    func scrollToSelectedCell() {
        guard selectedRow < cells.count, selectedCol < cells[selectedRow].count else { return }
        let cell = cells[selectedRow][selectedCol]

        // Scroll to make the cell visible
        if let scrollView = enclosingScrollView {
            let cellRect = cell.frame
            scrollView.contentView.scrollToVisible(cellRect)
        }
    }

    func updateSelection() {
        for row in cells {
            for cell in row {
                cell.layer?.borderWidth = (cell.row == selectedRow && cell.col == selectedCol) ? 2 : 0
                cell.layer?.borderColor = NSColor.systemBlue.cgColor
            }
        }
    }

    func cellDidEndEditing(_ cell: CellTextField) {
        viewModel?.data[cell.row][cell.col] = cell.stringValue
        viewModel?.isModified = true
        cell.isEditable = false
        cell.isSelectable = false

        // Update selection to the edited cell
        selectedRow = cell.row
        selectedCol = cell.col

        // Restore focus to grid view and update selection
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateSelection()
            self.window?.makeFirstResponder(self)
        }
    }

    func performUndo() {
        // First check if we have a reload to undo
        if let lastReloadState = reloadUndoStack.popLast() {
            viewModel?.data = lastReloadState
            viewModel?.isModified = true
            reloadData()
            return
        }

        // Otherwise undo a cell edit
        guard let lastEdit = undoStack.popLast() else { return }
        viewModel?.data[lastEdit.row][lastEdit.col] = lastEdit.oldValue
        viewModel?.isModified = true
        reloadData()
    }

    func saveStateForReload() {
        guard let viewModel = viewModel else { return }
        // Deep copy the current data state
        reloadUndoStack.append(viewModel.data.map { $0.map { $0 } })
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

    // MARK: - Copy/Paste Support

    @objc func copy(_ sender: Any?) {
        guard selectedRow < cells.count, selectedCol < cells[selectedRow].count else { return }
        let cell = cells[selectedRow][selectedCol]
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(cell.stringValue, forType: .string)
    }

    @objc func cut(_ sender: Any?) {
        guard selectedRow < cells.count, selectedCol < cells[selectedRow].count else { return }
        let cell = cells[selectedRow][selectedCol]
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(cell.stringValue, forType: .string)

        // Clear the cell
        undoStack.append((row: selectedRow, col: selectedCol, oldValue: cell.stringValue))
        cell.stringValue = ""
        viewModel?.data[selectedRow][selectedCol] = ""
        viewModel?.isModified = true
    }

    @objc func paste(_ sender: Any?) {
        guard selectedRow < cells.count, selectedCol < cells[selectedRow].count else { return }
        let pasteboard = NSPasteboard.general
        guard let pastedString = pasteboard.string(forType: .string) else { return }

        let cell = cells[selectedRow][selectedCol]
        undoStack.append((row: selectedRow, col: selectedCol, oldValue: cell.stringValue))
        cell.stringValue = pastedString
        viewModel?.data[selectedRow][selectedCol] = pastedString
        viewModel?.isModified = true
    }
}

class CellTextField: NSTextField {
    var row: Int = 0
    var col: Int = 0
    weak var gridView: GridHostView?
    var originalValue: String = ""
    var editingCancelled: Bool = false

    override func cancelOperation(_ sender: Any?) {
        // Escape key was pressed
        editingCancelled = true
        stringValue = originalValue
        window?.makeFirstResponder(gridView)
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)

        if editingCancelled {
            editingCancelled = false
            gridView?.cancelEditing(self)
        } else {
            gridView?.cellDidEndEditing(self)
        }
    }
}
