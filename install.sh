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

# Prevent running as root
if [ "$(id -u)" -eq 0 ]; then
    echo -e "${RED}${BOLD}Error: Do not run this installer as root or with sudo!${RESET}"
    echo "The OneSpan NativeBridge and user systemd service must run under your standard user account."
    echo "If root permissions are needed for system packages, you will be prompted automatically."
    exit 1
fi

UPGRADE_MODE=0
for arg in "$@"; do
    case "$arg" in
        --upgrade|-u|--reinstall|--force)
            UPGRADE_MODE=1
            ;;
        --help|-h)
            echo "Usage: ./install.sh [options]"
            echo ""
            echo "Options:"
            echo "  --upgrade, -u, --reinstall   Force re-running the Windows installer to update/upgrade"
            echo "  --help, -h                   Show this help message"
            exit 0
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIM_SRC="$SCRIPT_DIR/pcsc_shim.c"

# Support custom WINEPREFIX or default ~/.wine
WINE_PREFIX="${WINEPREFIX:-$HOME/.wine}"
export WINEPREFIX="$WINE_PREFIX"

# Support XDG base directories
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

SHIM_LIB_DIR="$HOME/.local/lib"
SHIM_LIB="$SHIM_LIB_DIR/libpcsc_wine_shim.so"
BIN_DIR="$HOME/.local/bin"
SERVICE_DIR="$XDG_CONFIG_HOME/systemd/user"
SERVICE_FILE="$SERVICE_DIR/digipass-nativebridge.service"
AUTOSTART_DIR="$XDG_CONFIG_HOME/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/digipass-nativebridge.desktop"
OFFICIAL_SHA256="e3c70d7fb4e7f5c388d301dcf82aea6c9070691f020a831a10aa6e691893bd27"

echo -e "${BOLD}====================================================${RESET}"
echo -e "${BOLD}   Belfius DIGIPASS 870 / OneSpan NativeBridge      ${RESET}"
echo -e "${BOLD}             Linux Auto-Installer                   ${RESET}"
echo -e "${BOLD}====================================================${RESET}\n"

# Helper to cleanly stop wine processes
stop_wine_processes() {
    systemctl --user stop digipass-nativebridge.service 2>/dev/null || true
    if command -v wineserver >/dev/null 2>&1; then
        wineserver -k 2>/dev/null || true
    elif command -v wine >/dev/null 2>&1; then
        wine wineserver -k 2>/dev/null || true
    fi
}

# Helper to find NativeBridge installation directory dynamically
find_bridge_dir() {
    local pfx="$1"
    # Check common fast paths first
    for d in "$pfx"/drive_c/users/*/AppData/Local/OneSpan/NativeBridge \
             "$pfx"/drive_c/users/*/AppData/Roaming/OneSpan/NativeBridge \
             "$pfx"/drive_c/"Program Files"/OneSpan/NativeBridge \
             "$pfx"/drive_c/"Program Files (x86)"/OneSpan/NativeBridge; do
        if [ -d "$d" ] && [ -f "$d/digipass-nativebridge.exe" ]; then
            echo "$d"
            return 0
        fi
    done

    # Fallback to case-insensitive recursive search across drive_c
    local found_exe
    found_exe=$(find "$pfx/drive_c" -maxdepth 6 -type f -iname "digipass-nativebridge.exe" 2>/dev/null | head -n 1)
    if [ -n "$found_exe" ]; then
        dirname "$found_exe"
        return 0
    fi
    return 1
}

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
            echo "Install: wine, pcsc-lite, ccid driver, and gcc/clang via your package manager."
            ;;
    esac
}

echo -e "${YELLOW}[1/6] Checking system requirements for: ${BOLD}${DISTRO_NAME}${RESET}..."

MISSING_DEPS=()
WINE_BIN="$(command -v wine 2>/dev/null || true)"
[ -z "$WINE_BIN" ] && MISSING_DEPS+=("wine")

# Support either gcc or clang
CC_BIN="${CC:-}"
if [ -z "$CC_BIN" ]; then
    if command -v gcc >/dev/null 2>&1; then
        CC_BIN="gcc"
    elif command -v clang >/dev/null 2>&1; then
        CC_BIN="clang"
    else
        MISSING_DEPS+=("gcc or clang (C compiler)")
    fi
fi

# Check if libpcsclite is present
if ! ldconfig -p 2>/dev/null | grep -q "libpcsclite\.so" && \
   [ ! -f /usr/lib64/libpcsclite.so.1 ] && \
   [ ! -f /usr/lib/x86_64-linux-gnu/libpcsclite.so.1 ] && \
   [ ! -f /usr/lib/libpcsclite.so.1 ] && \
   [ ! -f /usr/local/lib/libpcsclite.so.1 ]; then
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
echo -e "${GREEN}✓ All required tools and libraries are installed (${CC_BIN}, ${WINE_BIN}).${RESET}"

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

# 3. Check for NativeBridge installation / upgrade in Wine
echo -e "${YELLOW}[3/6] Checking OneSpan NativeBridge in Wine prefix (${WINE_PREFIX})...${RESET}"

BRIDGE_DIR="$(find_bridge_dir "$WINE_PREFIX" || true)"

if [ -z "$BRIDGE_DIR" ] || [ "$UPGRADE_MODE" -eq 1 ]; then
    if [ "$UPGRADE_MODE" -eq 1 ] && [ -n "$BRIDGE_DIR" ]; then
        echo "Upgrade/reinstall requested. Re-running Windows installer..."
    else
        echo "NativeBridge is not yet installed in Wine prefix."
    fi

    INSTALLER=$(find "$SCRIPT_DIR" "$HOME/Downloads" -maxdepth 2 -type f -name "digipass-nativebridge-installer.exe" 2>/dev/null | head -n 1)
    if [ -n "$INSTALLER" ]; then
        echo "Found installer at: $INSTALLER"
        ACTUAL_SHA256=$(sha256sum "$INSTALLER" | awk '{print $1}')
        if [ "$ACTUAL_SHA256" = "$OFFICIAL_SHA256" ]; then
            echo -e "${GREEN}✓ Installer integrity verified (SHA-256 matches known Belfius release).${RESET}"
        else
            echo -e "${YELLOW}Notice: Installer SHA-256 is $ACTUAL_SHA256 (new version or customized build).${RESET}"
        fi
        echo "Running Windows installer via Wine... (follow the on-screen prompts)"
        stop_wine_processes
        "$WINE_BIN" "$INSTALLER"
        BRIDGE_DIR="$(find_bridge_dir "$WINE_PREFIX" || true)"
    else
        echo -e "${RED}Error: digipass-nativebridge-installer.exe not found!${RESET}"
        echo "Please download it from Belfius and place it in $SCRIPT_DIR, then re-run this script."
        exit 1
    fi
fi

if [ -z "$BRIDGE_DIR" ] || [ ! -f "$BRIDGE_DIR/digipass-nativebridge.exe" ]; then
    echo -e "${RED}Error: digipass-nativebridge.exe still not found in $WINE_PREFIX!${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ Found NativeBridge at: $BRIDGE_DIR${RESET}"

# 4. Build PC/SC Wine Shim
echo -e "${YELLOW}[4/6] Compiling PC/SC Wine shim with ${CC_BIN}...${RESET}"
mkdir -p "$SHIM_LIB_DIR"

if [ ! -f "$SHIM_SRC" ]; then
    echo -e "${RED}Error: $SHIM_SRC not found!${RESET}"
    exit 1
fi

"$CC_BIN" -Wall -Wextra -shared -fPIC -O2 -o "$SHIM_LIB" "$SHIM_SRC" -ldl
echo -e "${GREEN}✓ Compiled shim to $SHIM_LIB${RESET}"

# 5. Disable runaway watchdog monitor in Wine registry
echo -e "${YELLOW}[5/6] Disabling buggy monitor watchdog in Wine registry...${RESET}"
stop_wine_processes
killall -q digipass-nativebridge-monitor.exe 2>/dev/null || true
killall -q digipass-nativebridge.exe 2>/dev/null || true
"$WINE_BIN" reg delete "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" /v DigipassNativeBridge /f 2>/dev/null || true
"$WINE_BIN" reg delete "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" /v OneSpanNativeBridge /f 2>/dev/null || true

# 6. Install autostart service and CLI helper
echo -e "${YELLOW}[6/6] Setting up background service and command helper...${RESET}"
mkdir -p "$BIN_DIR"
cat << HELPER_EOF > "$BIN_DIR/digipass-nativebridge"
#!/usr/bin/env bash
WINE_PREFIX="${WINE_PREFIX}"
export WINEPREFIX="\$WINE_PREFIX"
SHIM_LIB="$SHIM_LIB"

# Dynamically find bridge executable
BRIDGE_DIR=""
for d in "\$WINE_PREFIX"/drive_c/users/*/AppData/Local/OneSpan/NativeBridge \
         "\$WINE_PREFIX"/drive_c/users/*/AppData/Roaming/OneSpan/NativeBridge \
         "\$WINE_PREFIX"/drive_c/"Program Files"/OneSpan/NativeBridge; do
    if [ -d "\$d" ] && [ -f "\$d/digipass-nativebridge.exe" ]; then
        BRIDGE_DIR="\$d"
        break
    fi
done

if [ -z "\$BRIDGE_DIR" ]; then
    found=\$(find "\$WINE_PREFIX/drive_c" -maxdepth 6 -type f -iname "digipass-nativebridge.exe" 2>/dev/null | head -n 1)
    [ -n "\$found" ] && BRIDGE_DIR=\$(dirname "\$found")
fi

if [ -z "\$BRIDGE_DIR" ]; then
    echo "Error: NativeBridge directory not found in \$WINE_PREFIX" >&2
    exit 1
fi

killall -q digipass-nativebridge.exe 2>/dev/null || true
cd "\$BRIDGE_DIR"
export LD_PRELOAD="\$SHIM_LIB"
exec "$WINE_BIN" digipass-nativebridge.exe "\$@"
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
Environment="WINEPREFIX=$WINE_PREFIX"
Environment="LD_PRELOAD=$SHIM_LIB"
Environment="WINEDEBUG=-all"
ExecStart=$WINE_BIN "$BRIDGE_DIR/digipass-nativebridge.exe"
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
