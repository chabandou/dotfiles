# Noctalia Shell Module

This module tracks your Noctalia user configuration:

- `~/.config/noctalia`
- `~/.config/quickshell/noctalia-shell`
- `~/.config/systemd/user/noctalia.service.d/override.conf`

## Import current config

```bash
cd ~/dotfiles
./scripts/import-configs.sh
```

## Setup on a new machine

```bash
cd ~/dotfiles
./scripts/setup-noctalia-shell.sh
```

The setup script will:

1. Install `quickshell` and `noctalia-shell` (automatic on pacman systems).
2. Stow the `noctalia-shell` module.
3. Enable and start `noctalia.service` for the current user.

## Useful commands

```bash
systemctl --user status noctalia.service
journalctl --user -u noctalia.service -f
```
