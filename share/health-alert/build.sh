#!/bin/sh
# Build ~/Applications/Health Alert.app from HealthAlert.applescript.
#
# The applet is marked LSUIElement so it shows no Dock icon while it runs, and
# is signed ad hoc again after that change, because editing Info.plist breaks
# the signature osacompile made.

set -eu

here=$(cd "$(dirname "$0")" && pwd)
app="${HOME}/Applications/Health Alert.app"

mkdir -p "${HOME}/Applications"
rm -rf "$app"
osacompile -o "$app" "$here/HealthAlert.applescript"
plutil -replace LSUIElement -bool true "$app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string local.health-alert "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify "$app"
echo "built $app"
