#!/usr/bin/env bash
set -e

# ==============================================================================
# Belfius DIGIPASS 870 (OneSpan Native Bridge) Linux Setup Script
# ==============================================================================

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIM_SRC="$SCRIPT_DIR/pcsc_shim.c"
SHIM_LIB_DIR="$HOME/.local/lib"
SHIM_LIB="$SHIM_LIB_DIR/libpcsc_wine_shim.so"
BIN_DIR="$HOME/.local/bin"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/digipass-nativebridge.service"

echo -e "${BOLD}====================================================${RESET}"
echo -e "${BOLD}   Belfius DIGIPASS 870 / OneSpan NativeBridge      ${RESET}"
echo -e "${BOLD}             Linux Auto-Installer                   ${RESET}"
echo -e "${BOLD}====================================================${RESET}\n"

# 1. Dependency checks
echo -e "${YELLOW}[1/6] Checking system requirements...${RESET}"

MISSING_DEPS=""
command -v wine >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS wine"
command -v gcc >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS gcc"

if [ -n "$MISSING_DEPS" ]; then
    echo -e "${RED}Error: Missing required packages:${MISSING_DEPS}${RESET}\n"
    echo "Please install them via your distribution's package manager:"
    echo "  Fedora / RHEL:   sudo dnf install wine wine-smartcard pcsc-lite pcsc-lite-ccid gcc"
    echo "  Ubuntu / Debian: sudo apt install wine wine64 pcscd libpcsclite1 libccid build-essential"
    echo "  Arch Linux:      sudo pacman -S wine pcsclite ccid gcc"
    exit 1
fi

# 2. Check pcscd smart card service
echo -e "${YELLOW}[2/6] Verifying pcscd service...${RESET}"
if ! systemctl is-active --quiet pcscd 2>/dev/null && ! pgrep -x pcscd >/dev/null 2>&1; then
    echo "Starting and enabling pcscd system service..."
    if command -v sudo >/dev/null 2>&1; then
        sudo systemctl enable --now pcscd || true
    else
        echo -e "${YELLOW}Warning: pcscd is not active. Please run: sudo systemctl enable --now pcscd${RESET}"
    fi
else
    echo -e "${GREEN}pcscd daemon is active.${RESET}"
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
echo -e "${GREEN}Found NativeBridge at: $BRIDGE_DIR${RESET}"

# 4. Build PC/SC Wine Shim
echo -e "${YELLOW}[4/6] Compiling PC/SC Wine shim...${RESET}"
mkdir -p "$SHIM_LIB_DIR"

if [ ! -f "$SHIM_SRC" ]; then
    echo -e "${RED}Error: $SHIM_SRC not found!${RESET}"
    exit 1
fi

gcc -shared -fPIC -O2 -o "$SHIM_LIB" "$SHIM_SRC" -ldl
echo -e "${GREEN}Compiled shim to $SHIM_LIB${RESET}"

# 5. Disable runaway watchdog monitor in Wine registry
echo -e "${YELLOW}[5/6] Disabling buggy monitor watchdog in Wine registry...${RESET}"
killall -q digipass-nativebridge-monitor.exe 2>/dev/null || true
killall -q digipass-nativebridge.exe 2>/dev/null || true
wine reg delete "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" /v DigipassNativeBridge /f 2>/dev/null || true

# 6. Install systemd user service and CLI helper
echo -e "${YELLOW}[6/6] Setting up systemd user service and command helper...${RESET}"
mkdir -p "$BIN_DIR"
cat << 'EOF' > "$BIN_DIR/digipass-nativebridge"
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
export PCSC_SHIM_LOG="/tmp/pcsc_shim.log"
exec /usr/bin/wine digipass-nativebridge.exe "$@"
EOF
chmod +x "$BIN_DIR/digipass-nativebridge"

mkdir -p "$SERVICE_DIR"
cat << EOF > "$SERVICE_FILE"
[Unit]
Description=OneSpan DIGIPASS Native Bridge (Wine with PC/SC Shim)
After=network.target

[Service]
Type=simple
WorkingDirectory=$BRIDGE_DIR
Environment="LD_PRELOAD=$SHIM_LIB"
Environment="PCSC_SHIM_LOG=/tmp/pcsc_shim.log"
Environment="WINEDEBUG=-all"
ExecStart=/usr/bin/wine "$BRIDGE_DIR/digipass-nativebridge.exe"
Restart=on-failure
RestartSec=3s
TimeoutStopSec=3s
KillMode=mixed

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now digipass-nativebridge.service

sleep 2

if systemctl --user is-active --quiet digipass-nativebridge.service; then
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
    echo "  systemctl --user status digipass-nativebridge.service"
    echo "  journalctl --user -u digipass-nativebridge.service"
fi
