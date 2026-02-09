#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=0
RUN_BIGBAG_INSTALL=1
RUN_NOCTALIA=1
RUN_KANATA=1
RUN_SYSTEM_KEYBOARD=1
BIGBAG_REF=""

usage() {
  cat <<USAGE
Usage: ./scripts/bootstrap-arch.sh [options]

Runs full fresh-Arch setup for this dotfiles repo:
1) stow/link all modules
2) download + install DreymaR BigBag XKB files
3) setup Noctalia shell
4) enable kanata.service (user)
5) apply system keyboard via localectl from saved snapshot

Options:
  --dry-run               Print commands without executing
  --skip-bigbag           Skip BigBag install
  --skip-xkb-overlay      Alias of --skip-bigbag (backward compatibility)
  --bigbag-ref REF        Install specific BigBag git ref (branch/tag/commit)
  --skip-noctalia         Skip Noctalia setup
  --skip-kanata           Skip kanata.service enable/start
  --skip-system-keyboard  Skip localectl keyboard apply
  -h, --help              Show this help
USAGE
}

log() {
  printf '[bootstrap-arch] %s\n' "$*"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi

  "$@"
}

apply_system_keyboard_from_snapshot() {
  local snapshot keymap xkblayout xkbmodel xkbvariant xkboptions

  if ! has_cmd localectl; then
    log "localectl not found; skipping system keyboard apply"
    return
  fi

  snapshot="$DOTFILES_DIR/keyboard/.config/keyboard-system/vconsole.conf"
  if [[ ! -f "$snapshot" ]]; then
    log "No keyboard snapshot found at $snapshot; skipping"
    return
  fi

  keymap="$(awk -F= '/^KEYMAP=/{print $2}' "$snapshot" | tail -n1)"
  xkblayout="$(awk -F= '/^XKBLAYOUT=/{print $2}' "$snapshot" | tail -n1)"
  xkbmodel="$(awk -F= '/^XKBMODEL=/{print $2}' "$snapshot" | tail -n1)"
  xkbvariant="$(awk -F= '/^XKBVARIANT=/{print $2}' "$snapshot" | tail -n1)"
  xkboptions="$(awk -F= '/^XKBOPTIONS=/{print $2}' "$snapshot" | tail -n1)"

  if [[ -n "$keymap" ]]; then
    run sudo localectl set-keymap "$keymap"
  fi

  if [[ -n "$xkblayout" ]]; then
    run sudo localectl set-x11-keymap "$xkblayout" "$xkbmodel" "$xkbvariant" "$xkboptions"
  fi
}

enable_kanata_service() {
  local user_service_path

  if ! has_cmd systemctl; then
    log "systemctl not found; skipping kanata.service enable"
    return
  fi

  user_service_path="$HOME/.config/systemd/user/kanata.service"
  if [[ ! -f "$user_service_path" ]]; then
    log "kanata.service not found at $user_service_path; skipping"
    return
  fi

  run systemctl --user daemon-reload
  run systemctl --user enable --now kanata
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --skip-bigbag)
        RUN_BIGBAG_INSTALL=0
        ;;
      --skip-xkb-overlay)
        RUN_BIGBAG_INSTALL=0
        ;;
      --bigbag-ref)
        BIGBAG_REF="$2"
        shift
        ;;
      --skip-noctalia)
        RUN_NOCTALIA=0
        ;;
      --skip-kanata)
        RUN_KANATA=0
        ;;
      --skip-system-keyboard)
        RUN_SYSTEM_KEYBOARD=0
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

  cd "$DOTFILES_DIR"

  log "Linking dotfiles modules"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    run "$DOTFILES_DIR/install.sh" --dry-run --no-install-deps
  else
    run "$DOTFILES_DIR/install.sh"
  fi

  if [[ "$RUN_BIGBAG_INSTALL" -eq 1 ]]; then
    log "Installing DreymaR BigBag XKB files"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      if [[ -n "$BIGBAG_REF" ]]; then
        run "$DOTFILES_DIR/scripts/install-bigbag-xkb.sh" --dry-run --ref "$BIGBAG_REF"
      else
        run "$DOTFILES_DIR/scripts/install-bigbag-xkb.sh" --dry-run
      fi
    else
      if [[ -n "$BIGBAG_REF" ]]; then
        run "$DOTFILES_DIR/scripts/install-bigbag-xkb.sh" --ref "$BIGBAG_REF"
      else
        run "$DOTFILES_DIR/scripts/install-bigbag-xkb.sh"
      fi
    fi
  fi

  if [[ "$RUN_NOCTALIA" -eq 1 ]]; then
    log "Setting up Noctalia shell"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      run "$DOTFILES_DIR/scripts/setup-noctalia-shell.sh" --dry-run
    else
      run "$DOTFILES_DIR/scripts/setup-noctalia-shell.sh"
    fi
  fi

  if [[ "$RUN_KANATA" -eq 1 ]]; then
    log "Enabling kanata.service"
    enable_kanata_service
  fi

  if [[ "$RUN_SYSTEM_KEYBOARD" -eq 1 ]]; then
    log "Applying system keyboard snapshot"
    apply_system_keyboard_from_snapshot
  fi

  log "Done. Log out/in or reboot to apply all session-level changes."
}

main "$@"
