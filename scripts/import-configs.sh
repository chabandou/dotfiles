#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${HOME}"
INCLUDE_LOCAL_BIN=0

usage() {
  cat <<USAGE
Usage: ./scripts/import-configs.sh [--include-local-bin]

Copies common dotfiles from $HOME into stow modules inside this repo.
By default it skips ~/.local/bin because it often contains compiled binaries.
USAGE
}

copy_item() {
  local src="$1"
  local dst="$2"

  if [[ ! -e "$src" ]]; then
    return
  fi

  mkdir -p "$(dirname "$dst")"
  rm -rf "$dst"

  if [[ -d "$src" ]]; then
    cp -a "$src" "$dst"
  else
    cp -a "$src" "$dst"
  fi

  printf '[import] %s -> %s\n' "$src" "$dst"
}

copy_text_executables_from_local_bin() {
  local src_dir="$HOME_DIR/.local/bin"
  local dst_dir="$DOTFILES_DIR/local-bin/.local/bin"
  local f mime

  if [[ ! -d "$src_dir" ]]; then
    return
  fi

  mkdir -p "$dst_dir"

  while IFS= read -r -d '' f; do
    mime="$(file -b --mime-type "$f" || true)"
    case "$mime" in
      text/*|application/x-shellscript|application/json|application/xml)
        cp -a "$f" "$dst_dir/$(basename "$f")"
        printf '[import] %s -> %s\n' "$f" "$dst_dir/$(basename "$f")"
        ;;
      *)
        ;;
    esac
  done < <(find "$src_dir" -maxdepth 1 -type f -perm -u+x -print0)
}

snapshot_localectl_status() {
  local dst="$DOTFILES_DIR/keyboard/.config/keyboard-system/localectl-status.txt"

  if ! command -v localectl >/dev/null 2>&1; then
    return
  fi

  mkdir -p "$(dirname "$dst")"
  if localectl status >"$dst" 2>/dev/null; then
    printf '[import] localectl status -> %s\n' "$dst"
  else
    rm -f "$dst"
  fi
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --include-local-bin)
        INCLUDE_LOCAL_BIN=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage
        exit 1
        ;;
    esac
    shift
  done

  copy_item "$HOME_DIR/.bashrc" "$DOTFILES_DIR/bash/.bashrc"
  copy_item "$HOME_DIR/.zshrc" "$DOTFILES_DIR/zsh/.zshrc"
  copy_item "$HOME_DIR/.profile" "$DOTFILES_DIR/profile/.profile"
  copy_item "$HOME_DIR/.gitconfig" "$DOTFILES_DIR/git/.gitconfig"
  copy_item "$HOME_DIR/.gitignore_global" "$DOTFILES_DIR/git/.gitignore_global"
  copy_item "$HOME_DIR/.tmux.conf" "$DOTFILES_DIR/tmux/.tmux.conf"
  copy_item "$HOME_DIR/.config/starship.toml" "$DOTFILES_DIR/starship/.config/starship.toml"
  copy_item "$HOME_DIR/.config/kitty" "$DOTFILES_DIR/kitty/.config/kitty"
  copy_item "$HOME_DIR/.config/nvim" "$DOTFILES_DIR/nvim/.config/nvim"
  copy_item "$HOME_DIR/.config/hypr/input.conf" "$DOTFILES_DIR/keyboard/.config/hypr/input.conf"
  copy_item "/usr/share/X11/xkb/symbols/colemak" "$DOTFILES_DIR/keyboard/.config/keyboard-system/xkb-symbols/colemak"
  copy_item "/etc/vconsole.conf" "$DOTFILES_DIR/keyboard/.config/keyboard-system/vconsole.conf"
  copy_item "/etc/X11/xorg.conf.d/00-keyboard.conf" "$DOTFILES_DIR/keyboard/.config/keyboard-system/00-keyboard.conf"
  snapshot_localectl_status
  copy_item "$HOME_DIR/.config/kanata" "$DOTFILES_DIR/kanata/.config/kanata"
  copy_item "$HOME_DIR/.config/systemd/user/kanata.service" "$DOTFILES_DIR/kanata/.config/systemd/user/kanata.service"
  copy_item "$HOME_DIR/.config/noctalia" "$DOTFILES_DIR/noctalia-shell/.config/noctalia"
  copy_item "$HOME_DIR/.config/quickshell/noctalia-shell" "$DOTFILES_DIR/noctalia-shell/.config/quickshell/noctalia-shell"
  copy_item "$HOME_DIR/.config/systemd/user/noctalia.service.d/override.conf" "$DOTFILES_DIR/noctalia-shell/.config/systemd/user/noctalia.service.d/override.conf"

  if [[ "$INCLUDE_LOCAL_BIN" -eq 1 ]]; then
    copy_text_executables_from_local_bin
  fi

  echo "[import] Done. Review files for secrets before committing."
}

main "$@"
