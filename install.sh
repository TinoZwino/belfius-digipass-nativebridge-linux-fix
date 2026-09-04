#!/usr/bin/env bash
set -e

# ==============================================================================
# Belfius DIGIPASS 870 (OneSpan Native Bridge) Linux Setup Script
# ==============================================================================

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
RESET="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIM_SRC="$SCRIPT_DIR/pcsc_shim.c"
SHIM_LIB_DIR="$HOME/.local/lib"
SHIM_LIB="$SHIM_LIB_DIR/libpcsc_wine_shim.so"
BIN_DIR="$HOME/.local/bin"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/digipass-nativebridge.service"
AUTOSTART_DIR="$HOME/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/digipass-nativebridge.desktop"
OFFICIAL_SHA256="e3c70d7fb4e7f5c388d301dcf82aea6c9070691f020a831a10aa6e691893bd27"

echo -e "${BOLD}====================================================${RESET}"
echo -e "${BOLD}   Belfius DIGIPASS 870 / OneSpan NativeBridge      ${RESET}"
echo -e "${BOLD}             Linux Auto-Installer                   ${RESET}"
echo -e "${BOLD}====================================================${RESET}\n"

# Distro detection
DISTRO_NAME="Linux"
DISTRO_ID=""
DISTRO_LIKE=""
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_NAME="${PRETTY_NAME:-$NAME}"
    DISTRO_ID="${ID:-}"
    DISTRO_LIKE="${ID_LIKE:-}"
fi

get_install_command() {
    case "$DISTRO_ID $DISTRO_LIKE" in
        *fedora*|*rhel*|*centos*|*almalinux*|*rocky*)
            echo "sudo dnf install wine wine-smartcard pcsc-lite pcsc-lite-ccid gcc"
            ;;
        *ubuntu*|*debian*|*linuxmint*|*pop*|*zorin*|*elementary*)
            echo "sudo apt update && sudo apt install wine wine64 pcscd libpcsclite1 libccid build-essential"
            ;;
        *arch*|*manjaro*|*endeavouros*|*garuda*|*artix*)
            echo "sudo pacman -S wine pcsclite ccid gcc"
            ;;
        *suse*|*opensuse*)
            echo "sudo zypper install wine pcsc-lite pcsc-ccid gcc"
            ;;
        *alpine*)
            echo "sudo apk add wine pcsc-lite ccid gcc musl-dev"
            ;;
        *void*)
            echo "sudo xbps-install -S wine pcsc-lite ccid gcc"
            ;;
        *)
            echo "Install: wine, pcsc-lite, ccid driver, and gcc via your package manager."
            ;;
    esac
}

echo -e "${YELLOW}[1/6] Checking system requirements for: ${BOLD}${DISTRO_NAME}${RESET}..."

MISSING_DEPS=()
command -v wine >/dev/null 2>&1 || MISSING_DEPS+=("wine")
command -v gcc >/dev/null 2>&1 || MISSING_DEPS+=("gcc (C compiler)")

# Check if libpcsclite is present
if ! ldconfig -p 2>/dev/null | grep -q "libpcsclite\.so" && \
   [ ! -f /usr/lib64/libpcsclite.so.1 ] && \
   [ ! -f /usr/lib/x86_64-linux-gnu/libpcsclite.so.1 ] && \
   [ ! -f /usr/lib/libpcsclite.so.1 ]; then
    MISSING_DEPS+=("pcsc-lite (libpcsclite.so.1)")
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo -e "\n${RED}${BOLD}Missing required dependencies:${RESET}"
    for dep in "${MISSING_DEPS[@]}"; do
        echo -e "  - ${RED}${dep}${RESET}"
    done
    echo -e "\n${BOLD}To install them on ${DISTRO_NAME}, run:${RESET}"
    echo -e "  ${GREEN}$(get_install_command)${RESET}\n"
    exit 1
fi
echo -e "${GREEN}✓ All required tools and libraries are installed.${RESET}"

# 2. Check pcscd smart card service
echo -e "${YELLOW}[2/6] Verifying pcscd smart card daemon...${RESET}"
if ! systemctl is-active --quiet pcscd 2>/dev/null && ! pgrep -x pcscd >/dev/null 2>&1; then
    echo "Starting and enabling pcscd system service..."
    if command -v sudo >/dev/null 2>&1; then
        sudo systemctl enable --now pcscd || true
    else
        echo -e "${YELLOW}Warning: pcscd is not active. Please run: sudo systemctl enable --now pcscd${RESET}"
    fi
else
    echo -e "${GREEN}✓ pcscd daemon is active.${RESET}"
fi

# 3. Check for NativeBridge installation in Wine
echo -e "${YELLOW}[3/6] Locating OneSpan NativeBridge in Wine prefix...${RESET}"

BRIDGE_DIR=""
for d in "$HOME"/.wine/drive_c/users/*/AppData/Local/OneSpan/NativeBridge; do
    if [ -d "$d" ] && [ -f "$d/digipass-nativebridge.exe" ]; then
        BRIDGE_DIR="$d"
        break
    fi
done

if [ -z "$BRIDGE_DIR" ]; then
    echo "NativeBridge is not yet installed in Wine."
    INSTALLER=$(find "$SCRIPT_DIR" "$HOME/Downloads" -maxdepth 2 -type f -name "digipass-nativebridge-installer.exe" 2>/dev/null | head -n 1)
    if [ -n "$INSTALLER" ]; then
        echo "Found installer at: $INSTALLER"
        ACTUAL_SHA256=$(sha256sum "$INSTALLER" | awk '{print $1}')
        if [ "$ACTUAL_SHA256" = "$OFFICIAL_SHA256" ]; then
            echo -e "${GREEN}✓ Installer integrity verified (SHA-256 match).${RESET}"
        else
            echo -e "${YELLOW}Notice: Installer SHA-256 is $ACTUAL_SHA256 (expected official Belfius $OFFICIAL_SHA256).${RESET}"
        fi
        echo "Running Windows installer via Wine... (follow the prompt on screen)"
        wine "$INSTALLER"
        for d in "$HOME"/.wine/drive_c/users/*/AppData/Local/OneSpan/NativeBridge; do
            if [ -d "$d" ] && [ -f "$d/digipass-nativebridge.exe" ]; then
                BRIDGE_DIR="$d"
                break
            fi
        done
    else
        echo -e "${RED}Error: digipass-nativebridge-installer.exe not found!${RESET}"
        echo "Please download it from Belfius and place it in $SCRIPT_DIR, then re-run this script."
        exit 1
    fi
fi

if [ -z "$BRIDGE_DIR" ] || [ ! -f "$BRIDGE_DIR/digipass-nativebridge.exe" ]; then
    echo -e "${RED}Error: digipass-nativebridge.exe still not found in $HOME/.wine!${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ Found NativeBridge at: $BRIDGE_DIR${RESET}"

# 4. Build PC/SC Wine Shim
echo -e "${YELLOW}[4/6] Compiling PC/SC Wine shim...${RESET}"
mkdir -p "$SHIM_LIB_DIR"

if [ ! -f "$SHIM_SRC" ]; then
    echo -e "${RED}Error: $SHIM_SRC not found!${RESET}"
    exit 1
fi

gcc -Wall -Wextra -shared -fPIC -O2 -o "$SHIM_LIB" "$SHIM_SRC" -ldl
echo -e "${GREEN}✓ Compiled shim to $SHIM_LIB${RESET}"

# 5. Disable runaway watchdog monitor in Wine registry
echo -e "${YELLOW}[5/6] Disabling buggy monitor watchdog in Wine registry...${RESET}"
systemctl --user stop digipass-nativebridge.service 2>/dev/null || true
wineserver -k 2>/dev/null || true
killall -q digipass-nativebridge-monitor.exe 2>/dev/null || true
killall -q digipass-nativebridge.exe 2>/dev/null || true
wine reg delete "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" /v DigipassNativeBridge /f 2>/dev/null || true

# 6. Install autostart service and CLI helper
echo -e "${YELLOW}[6/6] Setting up background service and command helper...${RESET}"
mkdir -p "$BIN_DIR"
cat << 'HELPER_EOF' > "$BIN_DIR/digipass-nativebridge"
#!/usr/bin/env bash
BRIDGE_DIR=""
for d in "$HOME"/.wine/drive_c/users/*/AppData/Local/OneSpan/NativeBridge; do
    if [ -d "$d" ] && [ -f "$d/digipass-nativebridge.exe" ]; then
        BRIDGE_DIR="$d"
        break
    fi
done
SHIM_LIB="$HOME/.local/lib/libpcsc_wine_shim.so"

if [ -z "$BRIDGE_DIR" ]; then
    echo "Error: NativeBridge directory not found in ~/.wine" >&2
    exit 1
fi

killall -q digipass-nativebridge.exe 2>/dev/null || true
cd "$BRIDGE_DIR"
export LD_PRELOAD="$SHIM_LIB"
exec /usr/bin/wine digipass-nativebridge.exe "$@"
HELPER_EOF
chmod +x "$BIN_DIR/digipass-nativebridge"

# Check if systemd user services are supported
SYSTEMD_AVAILABLE=0
if systemctl --user is-system-running >/dev/null 2>&1 || systemctl --user status >/dev/null 2>&1; then
    SYSTEMD_AVAILABLE=1
fi

if [ "$SYSTEMD_AVAILABLE" -eq 1 ]; then
    mkdir -p "$SERVICE_DIR"
    cat << SERVICE_EOF > "$SERVICE_FILE"
[Unit]
Description=OneSpan DIGIPASS Native Bridge (Wine with PC/SC Shim)
After=network.target

[Service]
Type=simple
WorkingDirectory=$BRIDGE_DIR
Environment="LD_PRELOAD=$SHIM_LIB"
Environment="WINEDEBUG=-all"
ExecStart=/usr/bin/wine "$BRIDGE_DIR/digipass-nativebridge.exe"
Restart=on-failure
RestartSec=3s
TimeoutStopSec=3s
KillMode=mixed

[Install]
WantedBy=default.target
SERVICE_EOF

    systemctl --user daemon-reload
    systemctl --user enable --now digipass-nativebridge.service
    sleep 2
else
    # Fallback to XDG autostart desktop entry for non-systemd distros
    echo "Configuring XDG desktop autostart (non-systemd environment)..."
    mkdir -p "$AUTOSTART_DIR"
    cat << AUTOSTART_EOF > "$AUTOSTART_FILE"
[Desktop Entry]
Type=Application
Name=OneSpan DIGIPASS Native Bridge
Exec=$BIN_DIR/digipass-nativebridge
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
AUTOSTART_EOF
    "$BIN_DIR/digipass-nativebridge" &
    sleep 2
fi

SERVICE_OK=0
if [ "$SYSTEMD_AVAILABLE" -eq 1 ]; then
    if systemctl --user is-active --quiet digipass-nativebridge.service; then
        SERVICE_OK=1
    fi
else
    if pgrep -f "digipass-nativebridge.exe" >/dev/null 2>&1; then
        SERVICE_OK=1
    fi
fi

if [ "$SERVICE_OK" -eq 1 ]; then
    echo -e "\n${GREEN}${BOLD}✓ Setup successful!${RESET}"
    if [ -f "$BRIDGE_DIR/port.conf" ]; then
        echo "Listening on port(s): $(tr '\n' ' ' < "$BRIDGE_DIR/port.conf")"
    fi
    echo -e "\n${BOLD}Next steps:${RESET}"
    echo "1. Plug in your DIGIPASS 870 card reader via USB with your bank card inserted."
    echo "2. Go to https://www.belfius.be and choose 'Aanmelden' -> 'Met USB-kabel'."
    echo "3. The card reader and card will be recognized automatically."
    echo "4. The service will automatically start on every user login."
else
    echo -e "${RED}Warning: Service failed to start. Check status using:${RESET}"
    if [ "$SYSTEMD_AVAILABLE" -eq 1 ]; then
        echo "  systemctl --user status digipass-nativebridge.service"
        echo "  journalctl --user -u digipass-nativebridge.service"
    else
        echo "  ps aux | grep digipass-nativebridge"
    fi
fi
