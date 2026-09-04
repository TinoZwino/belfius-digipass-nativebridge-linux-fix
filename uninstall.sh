#!/usr/bin/env bash
set -e

echo "Stopping and disabling digipass-nativebridge.service..."
systemctl --user stop digipass-nativebridge.service 2>/dev/null || true
systemctl --user disable digipass-nativebridge.service 2>/dev/null || true

rm -f "$HOME/.config/systemd/user/digipass-nativebridge.service"
rm -f "$HOME/.config/autostart/digipass-nativebridge.desktop"
rm -f "$HOME/.local/bin/digipass-nativebridge"
rm -f "$HOME/.local/lib/libpcsc_wine_shim.so"
rm -f "/tmp/pcsc_shim.log"

systemctl --user daemon-reload 2>/dev/null || true

killall -q digipass-nativebridge.exe 2>/dev/null || true
killall -q digipass-nativebridge-monitor.exe 2>/dev/null || true

echo "Uninstallation complete. (Wine prefix files in ~/.wine remain untouched)."
