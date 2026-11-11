#!/bin/zsh
# Regenerates docs/demo-before.gif and docs/demo-after.gif from docs/demo.md.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -O Sources/Shared/*.swift Scripts/demo-gif/main.swift -o build/demo-gif
./build/demo-gif docs/demo.md docs
