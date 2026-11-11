#!/bin/zsh
# MD Viewer installer: downloads the source, builds it on this Mac and installs it.
#   curl -fsSL https://raw.githubusercontent.com/ertuozdenli/mdviewer/main/install.sh | zsh
# Building locally means no prebuilt binary is downloaded and Gatekeeper has nothing to block.
set -euo pipefail

REPO_TARBALL="https://github.com/ertuozdenli/mdviewer/archive/refs/heads/main.tar.gz"

main() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "MD Viewer only runs on macOS." >&2
    exit 1
  fi

  # swiftc ships with the Xcode Command Line Tools; full Xcode is not needed.
  if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "The Xcode Command Line Tools are required to build MD Viewer." >&2
    echo "Install them with:  xcode-select --install" >&2
    echo "Then run this installer again." >&2
    exit 1
  fi

  local work
  work=$(mktemp -d)
  trap "rm -rf '$work'" EXIT

  echo "→ Downloading source"
  curl -fsSL "$REPO_TARBALL" | tar -xz -C "$work" --strip-components 1

  cd "$work"
  ./build.sh

  echo
  echo "Done. Select a Markdown file in Finder and press Space."
  echo "If the old preview still shows, run:  qlmanage -r && killall Finder"
}

main "$@"
