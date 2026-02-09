#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cat >&2 <<MSG
[deprecated] scripts/apply-xkb-bigbag-overlay.sh is deprecated.
[deprecated] Use: ./scripts/install-bigbag-xkb.sh
MSG

exec "$DOTFILES_DIR/scripts/install-bigbag-xkb.sh" "$@"
