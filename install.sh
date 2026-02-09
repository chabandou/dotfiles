#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_HOME="${HOME}"
DRY_RUN=0
INSTALL_DEPS=1
INSTALL_PACKAGES=0
ADOPT=0
MODULES=()

usage() {
  cat <<USAGE
Usage: ./install.sh [options] [module ...]

Options:
  --dry-run             Show what would be linked without changing files
  --no-install-deps     Do not try to install stow
  --install-packages    Install system packages from packages/* (if present)
  --adopt               Move existing files into this repo when conflicts exist
  --target PATH         Link dotfiles into PATH (default: $HOME)
  -h, --help            Show this help

Examples:
  ./install.sh --dry-run
  ./install.sh bash zsh nvim
  ./install.sh --install-packages --adopt
USAGE
}

log() {
  printf '[dotfiles] %s\n' "$*"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

detect_pkg_manager() {
  if has_cmd brew; then
    echo brew
  elif has_cmd apt-get; then
    echo apt
  elif has_cmd pacman; then
    echo pacman
  elif has_cmd dnf; then
    echo dnf
  elif has_cmd zypper; then
    echo zypper
  else
    echo unknown
  fi
}

install_stow() {
  if has_cmd stow; then
    return
  fi

  if [[ "$INSTALL_DEPS" -eq 0 ]]; then
    log "stow is missing. Install it manually, or rerun without --no-install-deps."
    exit 1
  fi

  local pm
  pm="$(detect_pkg_manager)"
  log "stow not found; installing with package manager: $pm"

  case "$pm" in
    brew)
      brew install stow
      ;;
    apt)
      sudo apt-get update
      sudo apt-get install -y stow
      ;;
    pacman)
      sudo pacman -Sy --needed stow
      ;;
    dnf)
      sudo dnf install -y stow
      ;;
    zypper)
      sudo zypper --non-interactive install stow
      ;;
    *)
      log "Could not detect a supported package manager. Install stow manually."
      exit 1
      ;;
  esac
}

discover_modules() {
  find "$DOTFILES_DIR" -mindepth 1 -maxdepth 1 -type d \
    ! -name .git ! -name scripts ! -name packages \
    -printf '%f\n' | sort
}

install_system_packages() {
  local pm
  pm="$(detect_pkg_manager)"

  case "$pm" in
    brew)
      if [[ -f "$DOTFILES_DIR/packages/Brewfile" ]]; then
        log "Installing packages from packages/Brewfile"
        brew bundle --file "$DOTFILES_DIR/packages/Brewfile"
      else
        log "No packages/Brewfile found; skipping package install"
      fi
      ;;
    apt)
      if [[ -f "$DOTFILES_DIR/packages/apt.txt" ]]; then
        log "Installing packages from packages/apt.txt"
        sudo xargs -a "$DOTFILES_DIR/packages/apt.txt" apt-get install -y
      else
        log "No packages/apt.txt found; skipping package install"
      fi
      ;;
    pacman)
      if [[ -f "$DOTFILES_DIR/packages/pacman.txt" ]]; then
        log "Installing packages from packages/pacman.txt"
        sudo pacman -S --needed --noconfirm $(cat "$DOTFILES_DIR/packages/pacman.txt")
      else
        log "No packages/pacman.txt found; skipping package install"
      fi
      ;;
    *)
      log "No package installer configured for this system; skipping package install"
      ;;
  esac
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --no-install-deps)
        INSTALL_DEPS=0
        ;;
      --install-packages)
        INSTALL_PACKAGES=1
        ;;
      --adopt)
        ADOPT=1
        ;;
      --target)
        TARGET_HOME="$2"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        MODULES+=("$1")
        ;;
    esac
    shift
  done

  if [[ ${#MODULES[@]} -eq 0 ]]; then
    mapfile -t MODULES < <(discover_modules)
  fi

  if [[ ${#MODULES[@]} -eq 0 ]]; then
    log "No modules found to stow in $DOTFILES_DIR"
    exit 1
  fi

  install_stow

  if [[ "$INSTALL_PACKAGES" -eq 1 ]]; then
    install_system_packages
  fi

  local -a stow_args
  stow_args=(--dir "$DOTFILES_DIR" --target "$TARGET_HOME" -Rv)
  if [[ "$DRY_RUN" -eq 1 ]]; then
    stow_args+=(-n)
  fi
  if [[ "$ADOPT" -eq 1 ]]; then
    stow_args+=(--adopt)
  fi

  log "Using target: $TARGET_HOME"
  log "Modules: ${MODULES[*]}"

  for module in "${MODULES[@]}"; do
    stow "${stow_args[@]}" "$module"
  done

  log "Done"
}

main "$@"
