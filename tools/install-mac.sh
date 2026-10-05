#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="/Applications"
APP_NAME="spark.app"

usage() {
  echo "Usage: $(basename "$0") [--dir DIR]"
  echo "  Installs spark.app to DIR (default: /Applications)"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)
      TARGET_DIR="${2:?missing value for --dir}"; shift 2;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/$APP_NAME"

if [ ! -d "$SRC" ]; then
  echo "error: $APP_NAME not found next to this script" >&2
  exit 1
fi

SUDO=""
if [ ! -w "$TARGET_DIR" ]; then
  SUDO="sudo"
fi

$SUDO rm -rf "$TARGET_DIR/$APP_NAME"
$SUDO cp -R "$SRC" "$TARGET_DIR/$APP_NAME"
$SUDO xattr -dr com.apple.quarantine "$TARGET_DIR/$APP_NAME" 2>/dev/null || true

echo "Spark installed to $TARGET_DIR/$APP_NAME"
echo "Note: the app is unsigned — on first launch, right-click it and choose Open."
