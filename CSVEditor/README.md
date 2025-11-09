# CSV/TSV Editor for macOS

A simple spreadsheet-like editor for CSV and TSV files built with SwiftUI.

## Features

- Open CSV and TSV files
- Excel/Numbers-like grid interface with column headers (A, B, C...) and row numbers
- Edit cells by double-clicking
- Automatically detects delimiter (comma or tab)
- Save changes back to the original file or save as new file
- Track modifications with visual indicator

## How to Build

1. Open `CSVEditor.xcodeproj` in Xcode
2. Select your target Mac as the build destination
3. Press `Cmd+R` to build and run

## How to Use

1. Click "Open File" or press `Cmd+O` to load a CSV or TSV file
2. Double-click any cell to edit its contents
3. Press Enter/Return to confirm changes
4. Click "Save" to save changes to the original file
5. Click "Save As..." to save to a new file

## Requirements

- macOS 13.0 or later
- Xcode 14.0 or later
