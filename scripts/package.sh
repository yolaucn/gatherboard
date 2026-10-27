#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
TASK_RELEASE_DIRECTORY="$TASK_ROOT/.build/ReleaseArtifact"
# Keep packaging separate from any copy already installed or opened by the user.
BOARD_OUTPUT_DIRECTORY="$TASK_RELEASE_DIRECTORY" /bin/zsh scripts/build.sh --universal
TASK_DOWNLOAD_DIRECTORY="$TASK_ROOT/website/dist/downloads"
mkdir -p "$TASK_DOWNLOAD_DIRECTORY"
TASK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TASK_ROOT/Resources/Info.plist")"
TASK_PKG="$TASK_DOWNLOAD_DIRECTORY/归拢-$TASK_VERSION-universal.pkg"
TASK_ZIP="$TASK_DOWNLOAD_DIRECTORY/归拢-$TASK_VERSION-universal.zip"
TASK_PAYLOAD="$(mktemp -d "$TASK_ROOT/.build/InstallerPayload.XXXXXX")"
ditto "$TASK_RELEASE_DIRECTORY/归拢.app" "$TASK_PAYLOAD/归拢.app"
# A non-relocatable component must be built in root mode with an explicit plist.
# Otherwise Installer may update a development copy instead of /Applications.
pkgbuild --root "$TASK_PAYLOAD" --component-plist "$TASK_ROOT/Resources/InstallerComponents.plist" --install-location /Applications --identifier local.gatherboard.mac --version "$TASK_VERSION" --ownership recommended "$TASK_PKG"
ditto -c -k --sequesterRsrc --keepParent "$TASK_RELEASE_DIRECTORY/归拢.app" "$TASK_ZIP"
/bin/zsh "$TASK_ROOT/scripts/verify-package.sh" "$TASK_PKG"
shasum -a 256 "$TASK_PKG" "$TASK_ZIP"
