#!/usr/bin/env bash
# Run SwiftLint from repository root. Pass-through: ./scripts/lint.sh --fix
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "error: swiftlint not found. Install: brew install swiftlint" >&2
  exit 127
fi

exec swiftlint "$@"
