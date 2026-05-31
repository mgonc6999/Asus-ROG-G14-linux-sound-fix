# 🔊 ASUS ROG Zephyrus G14/G16 (2024/2025) – Linux Sound Fix

> **Fork of [Emile86/Asus-ROG-G14-linux-sound-fix](https://github.com/Emile86/Asus-ROG-G14-linux-sound-fix)**  
> This fork applies bug fixes, broader distro support, and Fedora 44 / KDE compatibility on top of the original v1.4 script.

> ⚠️ Code generated with Claude Sonnet 4.6 — use at your own risk.

---

## ❗ Problems this script fixes

On many Linux installations, the ASUS ROG Zephyrus G14 and G16 suffer from the following audio problems:

- 🔈 System volume slider does not control subwoofer volume
- 🔊 Subwoofers remain loud even when overall volume is lowered
- 🎚️ Hardware speaker amplifiers (AMP1 / AMP2) are not synchronized with system volume
- 🔄 PipeWire ignores ALSA hardware mixer limits
- 🔥 Sudden volume spikes after boot or resume
- ⚠️ Inconsistent sound quality between reboots

As a result, lowering the system volume does not properly reduce bass output, leading to unbalanced or overly loud sound.

---

## ✅ What this script does

- Enables ALSA soft-mixer support in WirePlumber
- Increases volume compared to Windows defaults
- Allows PipeWire to correctly control ALSA hardware mixers
- Forces sane hardware amplifier levels on boot (Master, AMP1 Speaker, AMP2 Speaker)
- Ensures subwoofer volume follows the system volume
- Normalizes sound output for better balance and clarity
- Provides a clean install and full rollback option

---

## 🖥️ Supported distributions

The script detects distros by both `ID` and `ID_LIKE` from `/etc/os-release`, so most derivatives of supported families are automatically recognized.

| Distro | Matched via |
|--------|-------------|
| Ubuntu | direct |
| Kubuntu | direct |
| Debian | direct |
| Arch Linux | direct |
| CachyOS | direct |
| Fedora (all spins) | direct |
| Linux Mint | `ID_LIKE=ubuntu` |
| Pop!_OS | `ID_LIKE=ubuntu` |
| Zorin OS | `ID_LIKE=ubuntu` |
| elementary OS | `ID_LIKE=ubuntu` |
| Nobara | `ID_LIKE=fedora` |
| Manjaro | `ID_LIKE=arch` |
| EndeavourOS | `ID_LIKE=arch` |
| Garuda Linux | `ID_LIKE=arch` |
| Raspbian | `ID_LIKE=debian` |

Distros outside this list will show a "not supported – no warranty" warning but the script can still run.

---

## 📦 Dependencies

The script auto-installs missing dependencies on first run using your distro's package manager (`dnf5`, `dnf`, `apt-get`, or `pacman`):

| Package | Provides |
|---------|----------|
| `newt` / `whiptail` | Interactive TUI menu |
| `alsa-utils` | `amixer`, `aplay` |

---

## ▶️ Usage

```bash
chmod +x zephyrus-sound-fix.sh
./zephyrus-sound-fix.sh
```

Follow the on-screen menu:

1. **Install / Apply Fix** — detects your sound card, writes WirePlumber config and systemd service
2. **Repair Existing Installation** — re-applies config without uninstalling
3. **Uninstall / Rollback** — fully removes all changes
4. **Export Diagnostics** — saves a full diagnostic report to the script directory

> 🔁 A reboot is required after installation.

---

---

## 🔧 How it works

### WirePlumber config

Written to `~/.config/wireplumber/main.conf.d/99-alsasoftvol.conf`:

```
monitor.alsa.rules = [
  {
    matches = [ { device.name = "~alsa_card.*" } ]
    actions = {
      update-props = { api.alsa.use-software-mixer = true }
    }
  }
]
```

This enables ALSA soft-mixer mode so PipeWire can control hardware volume levels.

### systemd service

Written to `/etc/systemd/system/alsa-card-volume-cap.service`. Runs once at boot after `graphical.target`, sets Master, AMP1 Speaker, and AMP2 Speaker to 100% so PipeWire has full range to work with.

---

## 📋 Changelog

### v1.5.1
- Fixed systemd ordering cycle: `After=graphical.target` + `WantedBy=multi-user.target` caused a circular dependency on Fedora, preventing the service from running at boot. Changed to `After=multi-user.target`.
- Confirmed working on Fedora 44 KDE after cold boot.
- Removed SELinux warning and `check_selinux()` function: SELinux does not block `amixer` in this setup (confirmed via `ausearch`); the ordering cycle was the actual cause of boot failures.

### v1.5 (changes from upstream v1.4)

| # | Area | Change |
|---|------|--------|
| 1 | Distro support | Added `fedora` to supported list; added `ID_LIKE` matching for derivatives |
| 2 | Dependencies | Added `check_deps()` — auto-installs `newt` and `alsa-utils` via `dnf5`/`dnf`/`apt-get`/`pacman` |
| 3 | WirePlumber config dir | Changed to `main.conf.d` (correct path for WirePlumber 0.5+) |
| 4 | WirePlumber property | Fixed `api.alsa.soft-mixer` → `api.alsa.use-software-mixer` |
| 5 | systemd service | Fixed `After=` (removed non-existent system-level pipewire dep); added `RemainAfterExit=yes`; moved sleep to `ExecStartPre` |
| 7 | Card detection | Safer `awk` card index parsing with `+0` and `sort -un` |
| 8 | Repair | Fixed card ID extraction from service file to parse `-c` flag correctly |
| 9 | Script path | Fixed `BASH_SOURCE[0]` fallback for piped/sourced execution |
| 10 | Fallback menu | Added missing `*` default case for invalid input |
| 11 | Typo | Fixed "Insrease" in MODEL_INFO |
| 12 | Version | Bumped to 1.5.1 |

---

## 📌 Why this is needed

On the ASUS ROG Zephyrus G14 and G16, subwoofers are controlled by separate hardware amplifiers. By default, Linux does not correctly bind these amplifiers to the main system volume, which results in:

> *"The volume slider moves, but the bass stays loud."*

This script fixes that by synchronizing ALSA hardware controls with PipeWire volume management, making volume behavior consistent, predictable, and safe.

---

## 📄 License

GPL-3.0 — same as upstream. See [LICENSE](LICENSE).
