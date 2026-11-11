#!/bin/zsh
# Regenerates docs/demo.gif from docs/demo.md.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -O Sources/Shared/*.swift Scripts/demo-gif/main.swift -o build/demo-gif
./build/demo-gif docs/demo.md docs/demo.gif
