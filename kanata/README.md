# Kanata Dotfiles Module

This module tracks your Kanata config at:

- `~/.config/kanata/config.kbd`
- `~/.config/systemd/user/kanata.service`

## Validate config

```bash
kanata --check -c ~/.config/kanata/config.kbd
```

## Run manually

```bash
kanata -c ~/.config/kanata/config.kbd
```

## Avoid duplicate instances

Before starting a new one, check running processes:

```bash
pgrep -a kanata
```

Stop all running Kanata processes if needed:

```bash
pkill -x kanata
```

## Run as a persistent user service (recommended)

The service file is tracked in this repo:

- `kanata/.config/systemd/user/kanata.service`

After running `./install.sh`, reload and enable it:

```bash
systemctl --user daemon-reload
systemctl --user enable --now kanata
systemctl --user status kanata
```

Logs:

```bash
journalctl --user -u kanata -f
```

## Re-import into dotfiles

After editing your live config, sync it back to this repo:

```bash
cd ~/dotfiles
./scripts/import-configs.sh
```
