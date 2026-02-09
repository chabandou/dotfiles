#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/DreymaR/BigBagKbdTrixXKB.git"
REF=""
DRY_RUN=0
KEEP_WORKDIR=0
WORKDIR=""

usage() {
  cat <<USAGE
Usage: ./scripts/install-bigbag-xkb.sh [options]

Download and install DreymaR's Big Bag of Keyboard Tricks (XKB) using the
official install script from its repository.

Options:
  --ref REF         Git branch/tag/commit to checkout (default: repository default branch)
  --repo-url URL    Override repository URL
  --workdir PATH    Use an existing working directory
  --keep-workdir    Do not delete the temporary clone directory
  --dry-run         Print planned commands without executing
  -h, --help        Show this help
USAGE
}

log() {
  printf '[bigbag-install] %s\n' "$*"
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

ensure_tools() {
  local missing=0

  if ! has_cmd git; then
    echo "git is required" >&2
    missing=1
  fi

  if [[ "$EUID" -ne 0 ]] && ! has_cmd sudo; then
    echo "sudo is required when not running as root" >&2
    missing=1
  fi

  if [[ "$missing" -eq 1 ]]; then
    exit 1
  fi
}

main() {
  local clone_dir installer
  local -a clone_cmd install_cmd

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ref)
        REF="$2"
        shift
        ;;
      --repo-url)
        REPO_URL="$2"
        shift
        ;;
      --workdir)
        WORKDIR="$2"
        shift
        ;;
      --keep-workdir)
        KEEP_WORKDIR=1
        ;;
      --dry-run)
        DRY_RUN=1
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

  ensure_tools

  if [[ -z "$WORKDIR" ]]; then
    WORKDIR="$(mktemp -d)"
  fi

  if [[ "$KEEP_WORKDIR" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
    trap 'rm -rf "$WORKDIR"' EXIT
  fi

  clone_dir="$WORKDIR/BigBagKbdTrixXKB"
  clone_cmd=(git clone --depth 1)
  if [[ -n "$REF" ]]; then
    clone_cmd+=(--branch "$REF")
  fi
  clone_cmd+=("$REPO_URL" "$clone_dir")

  log "Cloning BigBag repository"
  run "${clone_cmd[@]}"

  installer="$clone_dir/install-dreymar-xmod.sh"
  if [[ "$DRY_RUN" -eq 0 && ! -f "$installer" ]]; then
    echo "Installer not found: $installer" >&2
    exit 1
  fi

  if [[ "$EUID" -eq 0 ]]; then
    install_cmd=(bash "$installer" -d "$clone_dir" -o)
  else
    install_cmd=(sudo bash "$installer" -d "$clone_dir" -o)
  fi

  log "Running official BigBag installer"
  run "${install_cmd[@]}"

  if [[ "$KEEP_WORKDIR" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
    log "Working directory kept at: $WORKDIR"
  fi

  log "Done"
}

main "$@"
