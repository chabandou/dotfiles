# Keyboard Layout Module

This module tracks your keyboard configuration files:

- `~/.config/hypr/input.conf`
- Snapshot files under `~/.config/keyboard-system/`

Current Hypr values in this repo copy:

- `kb_layout = us`
- `kb_variant = cmk_ed_dh`
- `kb_model = pc104awide`

## BigBag install strategy

This repo no longer stores patched XKB files.

Instead, setup installs DreymaR Big Bag directly from the official repository using:

```bash
./scripts/install-bigbag-xkb.sh
```

You can pin a ref when needed:

```bash
./scripts/install-bigbag-xkb.sh --ref <tag-or-branch>
```

## System keyboard snapshot files

Tracked in this repo:

- `keyboard/.config/keyboard-system/localectl-status.txt`
- `keyboard/.config/keyboard-system/vconsole.conf`
- `keyboard/.config/keyboard-system/00-keyboard.conf`

To apply these system-level values manually:

```bash
sudo localectl set-keymap fr
sudo localectl set-x11-keymap fr pc105 '' terminate:ctrl_alt_bksp
```

## Refresh after changes

```bash
cd ~/dotfiles
./scripts/import-configs.sh
```
