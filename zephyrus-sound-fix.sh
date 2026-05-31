#!/usr/bin/env bash

APP_NAME="ASUS ROG Zephyrus Sound Fix"
VERSION="1.5.1"

MODEL_INFO="Designed for ASUS ROG Zephyrus G14/G16 2024/2025

Fixes low speaker volume by:
• Enabling ALSA soft mixer (WirePlumber)
• Forcing AMP1 / AMP2 speaker gain at boot
• Preventing volume cap after reboot
• Syncs tweeter and subwoofers
• Increase speaker volume by ~10 dB
"

SERVICE_NAME="alsa-card-volume-cap"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

# WirePlumber 0.5+ (Fedora 44 / modern distros) uses main.conf.d
WIREPLUMBER_DIR="$HOME/.config/wireplumber/main.conf.d"
WIREPLUMBER_FILE="$WIREPLUMBER_DIR/99-alsasoftvol.conf"

LOG_FILE="/var/log/zephyrus-sound-fix.log"

# Base supported distro IDs — derivatives are matched via ID_LIKE (see is_supported_distro)
SUPPORTED_DISTROS=("ubuntu" "kubuntu" "arch" "cachyos" "debian" "fedora")

RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; RESET="\e[0m"

sudo -v || { echo "Sudo required"; exit 1; }

log() { echo "$(date '+%F %T') | $*" | sudo tee -a "$LOG_FILE" >/dev/null 2>&1; }

# -------- Dependency check --------
# Ensures whiptail (newt) and alsa-utils are present.
# Handles dnf5 (Fedora 41+), dnf, apt-get, and pacman.
check_deps() {
    local missing=()
    command -v whiptail >/dev/null || missing+=("newt")
    command -v amixer   >/dev/null || missing+=("alsa-utils")
    command -v aplay    >/dev/null || missing+=("alsa-utils")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Installing missing dependencies: ${missing[*]}"
        if command -v dnf5 >/dev/null; then
            sudo dnf5 install -y "${missing[@]}"
        elif command -v dnf >/dev/null; then
            sudo dnf install -y "${missing[@]}"
        elif command -v apt-get >/dev/null; then
            sudo apt-get install -y "${missing[@]}"
        elif command -v pacman >/dev/null; then
            sudo pacman -S --noconfirm "${missing[@]}"
        else
            echo "Cannot auto-install: ${missing[*]}. Please install them manually."
            exit 1
        fi
    fi
}

check_deps

# -------- Distro detection --------
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        ID="${ID,,}"
        ID_LIKE="${ID_LIKE,,}"
        echo "$ID|${ID_LIKE:-}|$PRETTY_NAME"
    else
        echo "unknown||Unknown"
    fi
}

# Returns 0 if the distro ID or any of its ID_LIKE tokens match a supported distro.
# This covers derivatives: Mint/Pop/Zorin (ubuntu), Manjaro/EndeavourOS (arch),
# Nobara (fedora), Raspbian (debian), etc.
is_supported_distro() {
    local id="$1"
    local id_like="$2"
    [[ " ${SUPPORTED_DISTROS[*]} " =~ " $id " ]] && return 0
    for like in $id_like; do
        [[ " ${SUPPORTED_DISTROS[*]} " =~ " $like " ]] && return 0
    done
    return 1
}

DISTRO_RAW=$(detect_distro)
DISTRO="${DISTRO_RAW%%|*}"
DISTRO_LIKE="${DISTRO_RAW#*|}"; DISTRO_LIKE="${DISTRO_LIKE%|*}"
DISTRO_PRETTY="${DISTRO_RAW##*|}"

if is_supported_distro "$DISTRO" "$DISTRO_LIKE"; then
    DISTRO_FRIENDLY="$DISTRO_PRETTY (Supported)"
else
    DISTRO_FRIENDLY="$DISTRO_PRETTY (Not supported – no warranty)"
fi

# -------- Helper functions --------
is_installed() { systemctl is-enabled "$SERVICE_NAME" >/dev/null 2>&1; }

get_card_name() {
    local idx="$1"
    aplay -l 2>/dev/null | awk -v c="card $idx:" '$0 ~ c {sub(/.*\[/,""); sub(/\].*/,""); print; exit}'
}

detect_cards() {
    recommended=(); partial=(); hdmi=()
    while read -r idx; do
        name="$(get_card_name "$idx")"
        [[ -z "$name" ]] && name="Unknown"

        controls=$(amixer -c "$idx" controls 2>/dev/null)
        amp1="No"; amp2="No"
        echo "$controls" | grep -q "AMP1 Speaker" && amp1="Yes"
        echo "$controls" | grep -q "AMP2 Speaker" && amp2="Yes"

        if [[ "$amp1" == "Yes" && "$amp2" == "Yes" ]]; then
            recommended+=("$idx" "$name | AMP1:$amp1 AMP2:$amp2 | ⭐ Recommended")
        elif echo "$controls" | grep -Eq "Speaker|AMP"; then
            partial+=("$idx" "$name | AMP1:$amp1 AMP2:$amp2 | Partial")
        else
            hdmi+=("$idx" "$name | AMP1:$amp1 AMP2:$amp2 | HDMI-only")
        fi
    done < <(aplay -l 2>/dev/null | awk '/^card [0-9]/ {print $2+0}' | sort -un)

    CARD_OPTIONS=("${recommended[@]}" "${partial[@]}" "${hdmi[@]}")
}

create_configs() {
    local card="$1"
    mkdir -p "$WIREPLUMBER_DIR"
    # api.alsa.use-software-mixer is the correct property name in WirePlumber 0.5+
    cat > "$WIREPLUMBER_FILE" <<EOF
monitor.alsa.rules = [
  {
    matches = [
      { device.name = "~alsa_card.*" }
    ]
    actions = {
      update-props = {
        api.alsa.use-software-mixer = true
      }
    }
  }
]
EOF

    # Note: pipewire.service and wireplumber.service are user-session services and
    # cannot be referenced in After= from a system service. multi-user.target avoids
    # instead. ExecStartPre sleep gives the user session time to initialize ALSA.
    sudo tee "$SERVICE_PATH" >/dev/null <<EOF
[Unit]
Description=Set max volume on ALSA card $card
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/amixer -c $card set Master 100%
ExecStart=/usr/bin/amixer -c $card set 'AMP1 Speaker' 100%
ExecStart=/usr/bin/amixer -c $card set 'AMP2 Speaker' 100%

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    sudo systemctl restart "$SERVICE_NAME" >/dev/null 2>&1
}


show_progress() {
    local title="$1"
    shift
    local steps=("$@")
    local total=${#steps[@]}
    local i=0

    if command -v whiptail >/dev/null; then
        (
            for step in "${steps[@]}"; do
                i=$((i+1))
                percent=$((i*100/total))
                echo "$percent"
                echo "# $step"
                sleep 0.5
            done
        ) | whiptail --title "$title" --gauge "Please wait..." 10 70 0
    else
        echo "$title"
        for step in "${steps[@]}"; do
            i=$((i+1))
            percent=$((i*100/total))
            echo -ne "[$percent%] $step\r"
            sleep 0.5
        done
        echo -e "\nDone!"
    fi
}

prompt_reboot() {
    if command -v whiptail >/dev/null; then
        whiptail --title "Reboot Recommended" \
            --yesno "⚠ A system reboot is recommended to apply all changes.\n\nDo you want to reboot now?" 10 60
        if [[ $? -eq 0 ]]; then
            sudo reboot
        else
            echo "Reboot skipped. Please reboot later."
        fi
    else
        read -rp "⚠ A reboot is recommended. Reboot now? (y/N): " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            sudo reboot
        else
            echo "Reboot skipped. Please reboot later."
        fi
    fi
}

install_fix() {
    detect_cards
    [[ ${#CARD_OPTIONS[@]} -eq 0 ]] && { echo "No valid ALSA cards found."; return; }

    CARD_ID=$(whiptail --title "Select ALSA Card" \
        --menu "Choose sound card:" 20 90 12 \
        "${CARD_OPTIONS[@]}" 3>&1 1>&2 2>&3)

    [[ -z "$CARD_ID" ]] && return

    steps=("Creating WirePlumber config" \
           "Writing systemd service" \
           "Reloading systemd" \
           "Enabling & starting service")

    show_progress "Installing Sound Fix" "${steps[@]}"

    create_configs "$CARD_ID"
    log "Installed on card $CARD_ID"


    whiptail --msgbox "✅ Installation complete." 8 60
    prompt_reboot
}

repair_fix() {
    if ! is_installed; then
        whiptail --msgbox "Fix not installed." 8 50
        return
    fi

    # Parse card number from the -c flag rather than relying on field position
    CARD_ID=$(grep 'amixer -c' "$SERVICE_PATH" 2>/dev/null | head -1 | \
        awk '{for(i=1;i<=NF;i++) if($i=="-c") {print $(i+1); exit}}')

    steps=("Updating WirePlumber config" \
           "Updating systemd service" \
           "Reloading systemd" \
           "Restarting service")

    show_progress "Repairing Sound Fix" "${steps[@]}"

    create_configs "$CARD_ID"
    log "Repair completed on card $CARD_ID"


    whiptail --msgbox "🔧 Repair completed successfully." 8 50
    prompt_reboot
}

uninstall_fix() {
    steps=("Stopping service" \
           "Disabling service" \
           "Removing systemd service file" \
           "Removing WirePlumber config" \
           "Reloading systemd")

    show_progress "Uninstalling Sound Fix" "${steps[@]}"

    sudo systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
    sudo rm -f "$SERVICE_PATH"
    rm -f "$WIREPLUMBER_FILE"
    sudo systemctl daemon-reload

    log "Uninstalled"
    whiptail --msgbox "🗑️ Sound fix removed." 8 50
    prompt_reboot
}

export_diagnostics() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd 2>/dev/null || echo "$HOME")"
    REPORT="$SCRIPT_DIR/zephyrus-sound-diagnostic-$(date +%F-%H%M%S).txt"
    {
        echo "=== Zephyrus Sound Diagnostic Report ==="
        echo "Date: $(date)"
        echo "--- System ---"
        uname -a 2>&1 || true
        echo "--- Distribution ---"
        cat /etc/os-release 2>&1 || true
        echo "--- ALSA Cards ---"
        aplay -l 2>&1 || true
        echo "--- Amixer Controls ---"
        amixer 2>&1 || true
        echo "--- Service Status ---"
        systemctl status "$SERVICE_NAME" 2>&1 || true
        echo "--- WirePlumber Config ---"
        cat "$WIREPLUMBER_FILE" 2>&1 || true
        echo "--- Installer Log ---"
        cat "$LOG_FILE" 2>&1 || true
    } > "$REPORT"
    log "Diagnostic report exported to $REPORT"

    if command -v whiptail >/dev/null; then
        whiptail --title "Export Completed" \
            --msgbox "Diagnostic export completed successfully.\n\nSaved at:\n$REPORT" 12 70
    else
        echo "✔ Diagnostic export completed successfully."
        echo "Saved at: $REPORT"
        read -p "Press Enter to continue..."
    fi
}

fallback_mode() {
    echo "$APP_NAME v$VERSION"
    echo "$MODEL_INFO"
    echo "Detected distro: $DISTRO_FRIENDLY"
    while true; do
        echo
        echo "1) Install"
        echo "2) Repair"
        echo "3) Uninstall"
        echo "4) Export Diagnostics"
        echo "5) Exit"
        read -p "Select option: " opt
        case $opt in
            1) install_fix ;;
            2) repair_fix ;;
            3) uninstall_fix ;;
            4) export_diagnostics ;;
            5) exit 0 ;;
            *) echo "Invalid option." ;;
        esac
    done
}

# ================== START ==================
if command -v whiptail >/dev/null; then
    whiptail --title "$APP_NAME v$VERSION" --msgbox "$MODEL_INFO" 16 70
    while true; do
        if is_installed; then STATUS="Installed ✅"; else STATUS="Not Installed ❌"; fi

        CHOICE=$(whiptail --title "$APP_NAME v$VERSION" \
            --menu "Status: $STATUS\nDistro: $DISTRO_FRIENDLY\n\nSelect an option:" 24 70 12 \
            "1" "Install / Apply Fix" \
            "2" "Repair Existing Installation" \
            "3" "Uninstall / Rollback" \
            "4" "Export Diagnostics" \
            "5" "Exit" 3>&1 1>&2 2>&3)
        [[ -z "$CHOICE" ]] && exit 0
        case $CHOICE in
            1) install_fix ;;
            2) repair_fix ;;
            3) uninstall_fix ;;
            4) export_diagnostics ;;
            5|"") exit 0 ;;
        esac
    done
else
    fallback_mode
fi
