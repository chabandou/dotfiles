#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$DOTFILES_DIR/packages"
mkdir -p "$PKG_DIR"

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

if has_cmd apt-get && has_cmd dpkg-query; then
  dpkg-query -W -f='${binary:Package}\n' | sort > "$PKG_DIR/apt.txt"
  echo "[packages] Wrote $PKG_DIR/apt.txt"
fi

if has_cmd brew; then
  brew bundle dump --file "$PKG_DIR/Brewfile" --force
  echo "[packages] Wrote $PKG_DIR/Brewfile"
fi

if has_cmd pacman; then
  pacman -Qqe | sort > "$PKG_DIR/pacman.txt"
  echo "[packages] Wrote $PKG_DIR/pacman.txt"
fi

echo "[packages] Done"
