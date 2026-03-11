#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"

echo ">>> swift build -c release"
swift build -c release

echo ">>> swift test"
swift test
