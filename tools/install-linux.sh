#!/usr/bin/env bash
set -euo pipefail

PREFIX="${HOME}/.local"
UNINSTALL=0

usage() {
  echo "Usage: $(basename "$0") [--prefix DIR] [--uninstall]"
  echo "  Installs Spark to PREFIX/share/spark (default: \$HOME/.local)"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)
      PREFIX="${2:?missing value for --prefix}"; shift 2;;
    --uninstall)
      UNINSTALL=1; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

APP_DIR="$PREFIX/share/spark"
ICON_FILE="$PREFIX/share/icons/spark.png"
DESKTOP_FILE="$PREFIX/share/applications/spark.desktop"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$UNINSTALL" -eq 1 ]; then
  rm -rf "$APP_DIR" "$ICON_FILE" "$DESKTOP_FILE"
  echo "Spark uninstalled from $PREFIX"
  exit 0
fi

if [ ! -x "$SCRIPT_DIR/spark/spark" ]; then
  echo "error: spark/spark bundle not found next to this script" >&2
  exit 1
fi

mkdir -p "$APP_DIR" "$PREFIX/share/icons" "$PREFIX/share/applications"
cp -r "$SCRIPT_DIR/spark/." "$APP_DIR/"
chmod +x "$APP_DIR/spark"

if [ -f "$SCRIPT_DIR/spark.png" ]; then
  cp "$SCRIPT_DIR/spark.png" "$ICON_FILE"
fi

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Spark
Comment=Remote client for opencode AI coding agent
Exec=$APP_DIR/spark
Icon=spark
Terminal=false
Type=Application
Categories=Development;Utility;
StartupWMClass=spark
EOF
chmod +x "$DESKTOP_FILE"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$PREFIX/share/applications/" || true
fi

echo "Spark installed to $APP_DIR"
