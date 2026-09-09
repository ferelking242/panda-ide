#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if command -v flutter >/dev/null 2>&1; then
  flutter pub get
else
  echo "Flutter is not installed; skipping Flutter dependency setup."
fi