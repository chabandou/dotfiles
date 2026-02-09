# Dotfiles Setup

This repo stores my machine's setup as reproducible dotfiles using GNU Stow.

## Layout

Each top-level folder is a Stow module:

- `bash/.bashrc` -> `~/.bashrc`
- `nvim/.config/nvim/*` -> `~/.config/nvim/*`
- `keyboard/.config/hypr/input.conf` -> `~/.config/hypr/input.conf`
- `keyboard/.config/keyboard-system/*` -> `~/.config/keyboard-system/*` (system keyboard snapshot)
- `kanata/.config/kanata/*` -> `~/.config/kanata/*`
- `noctalia-shell/.config/noctalia/*` -> `~/.config/noctalia/*`
- `noctalia-shell/.config/quickshell/noctalia-shell/*` -> `~/.config/quickshell/noctalia-shell/*`
- etc.

## Import current configs

```bash
cd ~/dotfiles
./scripts/import-configs.sh
# optional: include text-based scripts from ~/.local/bin
./scripts/import-configs.sh --include-local-bin
```

## Review before committing

- Remove secrets/tokens from tracked files.
- Keep private keys out of this repo (`~/.ssh`, GPG keys, etc.).

## Snapshot installed packages

```bash
cd ~/dotfiles
./scripts/snapshot-packages.sh
```

This writes package manifests into `packages/`.

## Link configs on current machine

```bash
cd ~/dotfiles
./install.sh --dry-run
./install.sh
```

If files already exist and you want Stow to adopt them into the repo:

```bash
./install.sh --adopt
```

## Reproduce on a fresh Arch install

```bash
sudo pacman -Syu --needed git
git clone https://github.com/chabandou/dotfiles.git ~/dotfiles
cd ~/dotfiles
./scripts/bootstrap-arch.sh
```
This single command sequence handles linking dotfiles, downloading/installing DreymaR BigBag,
Noctalia setup, kanata service enablement, and system keyboard apply from your saved snapshot.
