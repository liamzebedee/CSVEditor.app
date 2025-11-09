#!/bin/bash

cd "$(dirname "$0")/CSVEditor"

echo "Building CSVEditor..."
xcodebuild -project CSVEditor.xcodeproj -scheme CSVEditor -configuration Debug build 2>&1 | grep -E "(BUILD|error:|warning:)"

if [ $? -eq 0 ]; then
    echo "Killing existing instance..."
    killall CSVEditor 2>/dev/null

    echo "Launching CSVEditor..."
    open ~/Library/Developer/Xcode/DerivedData/CSVEditor-*/Build/Products/Debug/CSVEditor.app --args "$PWD/../sample.csv"
else
    echo "Build failed!"
    exit 1
fi
