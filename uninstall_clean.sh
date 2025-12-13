#!/bin/bash

APP_NAME="WhisperWrap"
BUNDLE_ID="com.akeslo.WhisperWrap"

echo "🗑️  Starting clean uninstallation of $APP_NAME..."

# 1. Kill the app if it's running
if pgrep -x "$APP_NAME" > /dev/null; then
    echo "⚠️  Killing running instance..."
    pkill -x "$APP_NAME"
fi

# 2. Remove from Applications
if [ -d "/Applications/$APP_NAME.app" ]; then
    echo "📂 Removing App from /Applications..."
    rm -rf "/Applications/$APP_NAME.app"
else
    echo "ℹ️  App not found in /Applications"
fi

# Remove from local build dir if user wants to be sure (optional, but good for "clean state")
echo "📂 Removing local build artifact..."
rm -rf "./$APP_NAME.app"

# 3. Clear Preferences and Caches
echo "🧹 Clearing preferences and caches..."
defaults delete "$BUNDLE_ID" 2>/dev/null
rm -rf "$HOME/Library/Containers/$BUNDLE_ID"
rm -rf "$HOME/Library/Application Support/$APP_NAME"
rm -rf "$HOME/Library/Caches/$BUNDLE_ID"

# 4. Reset Permissions (TCC)
echo "🔒 Resetting permissions..."

# Debug: Show what's in TCC database
echo "   🔍 Checking TCC database for WhisperWrap entries..."
if command -v sqlite3 &> /dev/null; then
    TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    if [ -f "$TCC_DB" ]; then
        # Search for various name formats (case-insensitive)
        FOUND_ENTRIES=$(sqlite3 "$TCC_DB" "SELECT service, client FROM access WHERE
            client LIKE '%WhisperWrap%' OR
            client LIKE '%whisperwrap%' OR
            client LIKE '%WhisperWrap.app%' OR
            client LIKE '%whisperwrap.app%' OR
            client LIKE '%$BUNDLE_ID%';" 2>/dev/null)
        if [ -n "$FOUND_ENTRIES" ]; then
            echo "   📋 Found TCC entries:"
            echo "$FOUND_ENTRIES" | while read -r line; do
                echo "      $line"
            done
        else
            echo "   ℹ️  No TCC entries found for WhisperWrap"
        fi
    fi
fi

# Try to reset with bundle ID
echo "   Trying bundle ID: $BUNDLE_ID"
tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null
if [ $? -eq 0 ]; then echo "   ✅ Microphone permissions reset"; else echo "   ℹ️  No microphone permissions to reset (already clean)"; fi

tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null
if [ $? -eq 0 ]; then echo "   ✅ Accessibility permissions reset"; else echo "   ℹ️  No accessibility permissions to reset (already clean)"; fi

tccutil reset AppleEvents "$BUNDLE_ID" 2>/dev/null

# If tccutil didn't work, try direct database manipulation
echo "   🔧 Attempting direct TCC database cleanup..."
if command -v sqlite3 &> /dev/null; then
    TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    if [ -f "$TCC_DB" ]; then
        # Check if database is writable
        if [ ! -w "$TCC_DB" ]; then
            echo "   ⚠️  TCC database is read-only or protected"
            echo "   ℹ️  This is normal on modern macOS - database is system-protected"
            echo "   💡 If you need to reset: Go to System Settings > Privacy & Security"
        else
            # Try to delete entries
            ERROR_OUTPUT=$(sqlite3 "$TCC_DB" "DELETE FROM access WHERE
                client LIKE '%WhisperWrap%' OR
                client LIKE '%whisperwrap%' OR
                client LIKE '%WhisperWrap.app%' OR
                client LIKE '%whisperwrap.app%' OR
                client LIKE '%$BUNDLE_ID%';" 2>&1)

            if [ $? -eq 0 ]; then
                # Check if any rows were deleted
                REMAINING=$(sqlite3 "$TCC_DB" "SELECT COUNT(*) FROM access WHERE
                    client LIKE '%WhisperWrap%' OR
                    client LIKE '%whisperwrap%' OR
                    client LIKE '%WhisperWrap.app%' OR
                    client LIKE '%whisperwrap.app%' OR
                    client LIKE '%$BUNDLE_ID%';" 2>/dev/null)
                echo "   ✅ Direct database cleanup completed"
                if [ "$REMAINING" = "0" ]; then
                    echo "   ✅ All WhisperWrap TCC entries removed"
                else
                    echo "   ⚠️  Some entries may remain: $REMAINING entries found"
                fi
                echo "   💡 Restart your Mac for changes to take full effect"
            else
                echo "   ⚠️  Database modification failed: $ERROR_OUTPUT"
                echo "   💡 Try: Close System Settings, then run: killall -9 cfprefsd tccd"
            fi
        fi
    else
        echo "   ℹ️  TCC database not found at expected location"
    fi
else
    echo "   ⚠️  sqlite3 not found - cannot check database"
fi

# 5. Remove Login Item
echo "🚀 Checking login items..."

# Check for LaunchAgents plist
if [ -f "$HOME/Library/LaunchAgents/$BUNDLE_ID.plist" ]; then
    echo "   Removing LaunchAgent plist..."
    rm "$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
    echo "   ✅ LaunchAgent removed"
fi

# Check SMAppService login items (macOS 13+)
echo "   Checking SMAppService login items..."
if sfltool dumpbtm 2>/dev/null | grep -i "whisperwrap" > /dev/null; then
    echo "   📋 Found in Background Task Management (SMAppService)"
    echo "   ℹ️  Login item will be removed automatically when app is deleted"
else
    echo "   ℹ️  No SMAppService login item found"
fi

# Try legacy System Events method
osascript -e "tell application \"System Events\" to delete login item \"$APP_NAME\"" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "   ✅ Removed legacy System Events login item"
else
    echo "   ℹ️  No legacy login items found"
fi

# Attempt to tell LaunchServices to rebuild database for this app (helps clear cached entries)
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "/Applications/$APP_NAME.app" 2>/dev/null

echo "✨ Clean uninstall complete! You can now build and reinstall a fresh version."
