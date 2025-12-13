#!/bin/bash

# Configuration
APP_NAME="WhisperWrap"
# Assuming the script is run from the project root where WhisperWrap.app is located
APP_BUNDLE="./WhisperWrap.app"
BINARY_PATH="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Check if app exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: $APP_BUNDLE not found. Make sure you have built the app."
    exit 1
fi

# Kill existing instances
echo "Stopping any running instances of $APP_NAME..."
pkill -x "$APP_NAME"
sleep 1

# Clear previous old log
rm -f "/tmp/ww_internal.log"

echo "Launching $APP_NAME in background (simulating Login Item mode)..."
echo "The app will REMAIN RUNNING so you can interact with it."

# Launch in background using nohup so it doesn't close when script ends
# We redirect stdout/stderr to /dev/null because we are using internal file logging
nohup "$BINARY_PATH" -backgroundLaunch > /dev/null 2>&1 &
NEW_PID=$!

echo "App launched with PID: $NEW_PID"
echo "Waiting 2 seconds for startup logs..."
sleep 2

echo "---------------------------------------------------"
if [ -f "/tmp/ww_internal.log" ]; then
    echo "📜 Internal Log Output (Startup Phase):"
    cat "/tmp/ww_internal.log"
else
    echo "⚠️ No internal log found (yet)."
fi
echo "---------------------------------------------------"
echo "Done. The app is still running."
