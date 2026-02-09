#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=0
INSTALL_PACKAGES=1
ENABLE_SERVICE=1
ADOPT=0

usage() {
  cat <<USAGE
Usage: ./scripts/setup-noctalia-shell.sh [options]

Installs Noctalia Shell packages (where supported), stows the noctalia-shell
module, and enables the user service.

Options:
  --dry-run               Show planned actions without changing anything
  --no-install-packages   Skip package installation
  --no-enable-service     Do not enable/start noctalia.service
  --adopt                 Pass --adopt when stowing files
  -h, --help              Show this help
USAGE
}

log() {
  printf '[noctalia-setup] %s\n' "$*"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

detect_pkg_manager() {
  if has_cmd pacman; then
    echo pacman
  elif has_cmd apt-get; then
    echo apt
  elif has_cmd dnf; then
    echo dnf
  elif has_cmd zypper; then
    echo zypper
  elif has_cmd brew; then
    echo brew
  else
    echo unknown
  fi
}

install_packages() {
  local pm

  if [[ "$INSTALL_PACKAGES" -eq 0 ]]; then
    log "Skipping package install"
    return
  fi

  pm="$(detect_pkg_manager)"

  case "$pm" in
    pacman)
      if [[ "$DRY_RUN" -eq 1 ]]; then
        log "Would run: sudo pacman -Sy --needed quickshell noctalia-shell"
      else
        sudo pacman -Sy --needed quickshell noctalia-shell
      fi
      ;;
    apt|dnf|zypper|brew)
      log "Automatic package install for '$pm' is not configured. Install 'quickshell' and 'noctalia-shell' manually."
      ;;
    *)
      log "No supported package manager detected. Install 'quickshell' and 'noctalia-shell' manually."
      ;;
  esac
}

stow_noctalia_module() {
  local -a args
  args=()

  if [[ "$DRY_RUN" -eq 1 ]]; then
    args+=(--dry-run)
    args+=(--no-install-deps)
  fi
  if [[ "$ADOPT" -eq 1 ]]; then
    args+=(--adopt)
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "Would run: ./install.sh ${args[*]} noctalia-shell"
    if ! has_cmd stow; then
      log "stow is not installed on this machine; skipping stow execution in dry-run"
      return
    fi
  fi

  "$DOTFILES_DIR/install.sh" "${args[@]}" noctalia-shell
}

enable_service() {
  if [[ "$ENABLE_SERVICE" -eq 0 ]]; then
    log "Skipping systemd service enable/start"
    return
  fi

  if ! has_cmd systemctl; then
    log "systemctl not found; cannot manage noctalia.service"
    return
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "Would run: systemctl --user daemon-reload"
    log "Would run: systemctl --user enable --now noctalia.service"
    return
  fi

  systemctl --user daemon-reload
  systemctl --user enable --now noctalia.service
  systemctl --user --no-pager --lines=5 status noctalia.service || true
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --no-install-packages)
        INSTALL_PACKAGES=0
        ;;
      --no-enable-service)
        ENABLE_SERVICE=0
        ;;
      --adopt)
        ADOPT=1
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

  install_packages
  stow_noctalia_module
  enable_service
  log "Done"
}

main "$@"
