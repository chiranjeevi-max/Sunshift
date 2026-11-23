#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --script res://tests/test_art.gd

printf '\nArt previews are in build/art_preview/.\n'
