#!/bin/bash
# Double-click to start Cellar web UI
# Opens http://127.0.0.1:8080 in your browser

cd "$(dirname "$0")" || exit 1

echo "Building Cellar..."
swift build 2>&1
if [ $? -ne 0 ]; then
    echo ""
    echo "Build failed. Make sure you have Swift installed (Xcode or swift.org toolchain)."
    read -rp "Press Enter to close..."
    exit 1
fi

CELLAR=.build/arm64-apple-macosx/debug/cellar

# Open browser after a short delay
(sleep 2 && open http://127.0.0.1:8080) &

echo ""
echo "Starting Cellar web UI..."
echo "Close this window to stop the server."
echo ""
$CELLAR serve
