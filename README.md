# Belfius DIGIPASS 870 on Linux (OneSpan NativeBridge + Wine Shim)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-orange.svg)](https://kernel.org)
[![Wine: 8.0+](https://img.shields.io/badge/Wine-8.0%2B%20%7C%209.0%2B%20%7C%2010.0%2B-blue.svg)](https://winehq.org)
[![Hardware: DIGIPASS 870](https://img.shields.io/badge/Hardware-VASCO%20%2F%20OneSpan%20870-brightgreen.svg)](https://www.onespan.com)
[![Authored by: AI](https://img.shields.io/badge/Authored%20by-Google%20Antigravity%20AI-purple.svg)](https://deepmind.google)

A turnkey, plug-and-play solution to run the **OneSpan (VASCO) DIGIPASS 870** smartcard reader natively on **Linux** for **Belfius Direct Net** online banking (`https://www.belfius.be`) via USB cable.

---

## Table of Contents

- [AI Authorship Disclosure](#ai-authorship-disclosure)
- [Project Overview](#project-overview)
- [The Problem (Why it Fails by Default)](#the-problem-why-it-fails-by-default)
  - [1. The 64-bit Wine `SCARD_AUTOALLOCATE` Bug](#1-the-64-bit-wine-scard_autoallocate-bug)
  - [2. The Runaway Watchdog Process Fork-Bomb](#2-the-runaway-watchdog-process-fork-bomb)
  - [3. Flatpak / Bottles Sandbox Confinement](#3-flatpak--bottles-sandbox-confinement)
- [How the Fix Works](#how-the-fix-works)
- [Prerequisites & Supported Distributions](#prerequisites--supported-distributions)
- [Supported Web Browsers](#supported-web-browsers)
- [Installation Tutorial](#installation-tutorial)
  - [Method A: Automated Installation (Recommended)](#method-a-automated-installation-recommended)
  - [Method B: Manual Installation](#method-b-manual-installation)
- [How to Log In to Belfius](#how-to-log-in-to-belfius)
- [Service Management & Troubleshooting](#service-management--troubleshooting)
- [Technical Upstream Notes (for WineHQ)](#technical-upstream-notes-for-winehq)
- [Uninstallation](#uninstallation)
- [License](#license)

---

## AI Authorship Disclosure

> **Note**: This entire repository, including the reverse-engineering analysis, C interceptor shim (`pcsc_shim.c`), systemd service integration, automated installer/uninstaller scripts, and documentation, was **100% researched, developed, debugged, and verified by an AI coding assistant (Google Antigravity / DeepMind)** paired with user [@TinoZwino](https://github.com/TinoZwino).
>
> During a real-time troubleshooting session, the AI systematically investigated why Belfius's official Windows bridge failed under Wine on Linux, pinpointed a subtle 64-bit zero-extension discrepancy in Wine's smartcard translation layer, detected an infinite process spawning loop in the Windows background monitor, wrote and compiled an `LD_PRELOAD` C shim to dynamically patch the ABI calls at runtime, and verified end-to-end PIN verification on the physical DIGIPASS 870 keypad.

---

## Project Overview

Belgian bank **Belfius** uses the **VASCO / OneSpan DIGIPASS 870** card reader for secure, high-limit online banking authentication. On Windows and macOS, Belfius provides a proprietary helper application called **OneSpan NativeBridge** (`digipass-nativebridge.exe`). 

When you navigate to `https://www.belfius.be` in any web browser, the website connects to a local WebSocket / HTTP server hosted on `127.0.0.1` (ports `42579` and `42580`) managed by NativeBridge. This bridge talks to the smartcard reader via Windows PC/SC APIs (`winscard.dll`), asks the reader to display security information, prompts the user to enter their PIN directly on the reader's physical keypad, and returns cryptographically signed APDU responses back to the bank.

Belfius **does not provide a Linux build** of NativeBridge. Running the Windows binary under Wine or Bottles historically failed with the website stuck indefinitely on **"Insert your card"**, even when the card reader was plugged in and detected.

**This project completely solves that problem.**

---

## The Problem (Why it Fails by Default)

Three major technical issues prevent the official Windows installer from working on Linux:

### 1. The 64-bit Wine `SCARD_AUTOALLOCATE` Bug
The official `digipass-nativebridge.exe` queries the smartcard's ATR (Answer To Reset) string using the Windows PC/SC function:
```c
SCardGetAttrib(hCard, SCARD_ATTR_ATR_STRING, (LPBYTE)&pbAttr, &dwAttrLen);
```
In the Windows SDK (`winscard.h`), automatic buffer allocation is requested by setting:
```c
#define SCARD_AUTOALLOCATE (DWORD)(-1) /* 0xFFFFFFFF */
```
When running under 64-bit Wine, Wine translates Win32 API calls into native Linux calls to `libpcsclite.so.1`. In Wine's `dlls/winscard/winscard.c` and `unixlib.c`, Wine reads the 32-bit `DWORD` from the Windows process and zero-extends it into a 64-bit host `unsigned long`:
```c
/* Wine 64-bit conversion: */
(unsigned long)0xFFFFFFFF  ==>  0x00000000FFFFFFFF
```
However, the 64-bit Linux PC/SC Lite header (`/usr/include/PCSC/winscard.h`) defines:
```c
#define SCARD_AUTOALLOCATE ((unsigned long)-1) /* 0xFFFFFFFFFFFFFFFF */
```
Because `0x00000000FFFFFFFF != 0xFFFFFFFFFFFFFFFF`, Linux's `libpcsclite` does not recognize `SCARD_AUTOALLOCATE`. Instead, it assumes the caller provided a regular buffer of size `4,294,967,295` bytes while passing a NULL destination pointer. `libpcsclite` immediately rejects the call with error code:
```
SCARD_E_INSUFFICIENT_BUFFER (0x80100008)
```
`digipass-nativebridge.exe` logs:
```
Card reader initialization failed: Internal error.
```
and drops the card session. The browser UI remains frozen on *"Insert your card"*.

### 2. The Runaway Watchdog Process Fork-Bomb
The installer creates a Windows registry autostart entry:
```
HKCU\Software\Microsoft\Windows\CurrentVersion\Run -> digipass-nativebridge-monitor.exe
```
This monitor process attempts to determine if `digipass-nativebridge.exe` is running by calling the Windows API:
```c
WTSEnumerateProcessesA(...)
```
In Wine, `WTSEnumerateProcessesA` is an unimplemented stub that returns `0` (failure/no processes). Believing the bridge has crashed, `digipass-nativebridge-monitor.exe` executes a new instance of `digipass-nativebridge.exe` every second in an infinite loop! Within a few minutes, hundreds of orphan Wine processes saturate system memory, crash `wineserver`, and lock ports 42579/42580.

### 3. Flatpak / Bottles Sandbox Confinement
Running the application inside sandbox runners like Bottles (Flatpak) isolates the application from the host smartcard daemon socket (`/run/pcscd/pcscd.comm`), and default Bottles runner builds do not compile Wine with PC/SC (`winscard`) support enabled.

---

## How the Fix Works

This project resolves every root cause cleanly and minimally:

1. **Dynamic PC/SC ABI Shim (`pcsc_shim.c`)**:
   A lightweight C shared library (`libpcsc_wine_shim.so`) is injected via `LD_PRELOAD` into the Wine environment. It intercepts `SCardGetAttrib`:
   ```c
   if (pcbAttrLen && *pcbAttrLen == 0xFFFFFFFFUL) {
       *pcbAttrLen = ((unsigned long)-1); /* Translates to 64-bit 0xFFFFFFFFFFFFFFFF */
   }
   ```
   `libpcsclite.so.1` now recognizes the auto-allocation request, allocates the ATR buffer, and returns `SCARD_S_SUCCESS` (`0x00000000`). It also handles protocol fallbacks (`SCARD_PROTOCOL_T0`) for card reader negotiation.

2. **Registry Watchdog Neutralization**:
   The installer removes `DigipassNativeBridge` from Wine's `Run` registry key, stopping the infinite fork-bomb permanently.

3. **Managed Systemd User Service**:
   Rather than relying on Windows-style background monitor executables, a native `systemd` user service (`digipass-nativebridge.service`) manages the bridge daemon cleanly in the background with auto-restart on failure and zero overhead.

---

## Prerequisites & Supported Distributions

`install.sh` **automatically detects your Linux distribution** and will print the exact package installation command for your specific system if any dependency is missing.

### OS Compatibility Matrix

| Distribution | Versions | Compatibility Status | Package Manager Command |
| :--- | :--- | :---: | :--- |
| **Fedora** | 39, 40, 41, Rawhide | **Fully Tested** | `sudo dnf install wine wine-smartcard pcsc-lite pcsc-lite-ccid gcc` |
| **Ubuntu** | 22.04 LTS, 24.04 LTS, 24.10+ | **Fully Supported** | `sudo apt install wine wine64 pcscd libpcsclite1 libccid build-essential` |
| **Debian** | 12 (Bookworm), 13 (Trixie), Sid | **Fully Supported** | `sudo apt install wine wine64 pcscd libpcsclite1 libccid build-essential` |
| **Linux Mint** | 21, 22+ | **Fully Supported** | `sudo apt install wine wine64 pcscd libpcsclite1 libccid build-essential` |
| **Pop!_OS / Zorin OS** | Current releases | **Fully Supported** | `sudo apt install wine wine64 pcscd libpcsclite1 libccid build-essential` |
| **Arch Linux** | Rolling | **Fully Supported** | `sudo pacman -S wine pcsclite ccid gcc` |
| **Manjaro / EndeavourOS** | Rolling | **Fully Supported** | `sudo pacman -S wine pcsclite ccid gcc` |
| **openSUSE** | Tumbleweed, Leap 15.5+ | **Fully Supported** | `sudo zypper install wine pcsc-lite pcsc-ccid gcc` |
| **RHEL / Alma / Rocky** | 9.x, 10.x | **Fully Supported** | `sudo dnf install wine wine-smartcard pcsc-lite pcsc-lite-ccid gcc` |
| **Fedora Silverblue / Bazzite** | Atomic / Immutable | **Supported** | `rpm-ostree install wine-smartcard pcsc-lite pcsc-lite-ccid` |
| **Non-systemd (Void, Alpine)** | Current | **Supported** | Auto-configures XDG `~/.config/autostart` desktop fallback |

> **Smartcard Daemon Check**: You can verify that your card reader is recognized by running:
> ```bash
> pcsc_scan
> ```
> When you insert your bank card, it should output `Card state: Card inserted` and print the card's ATR string. Press `Ctrl+C` to exit.

---

## Supported Web Browsers

Because the OneSpan NativeBridge communicates with your browser over standard local HTTP/WebSocket loopback (`127.0.0.1:42579` and `127.0.0.1:42580`), it is **completely browser-agnostic**. Any browser capable of accessing local loopback connections is supported.

### Browser Compatibility Matrix

| Browser | Engine / Core | Packaging Formats | Compatibility Status | Notes |
| :--- | :--- | :--- | :---: | :--- |
| **Mozilla Firefox** | Gecko | Native (.deb/.rpm), Flatpak, Snap | **Fully Supported** | Default browser across most Linux distros |
| **Google Chrome** | Chromium | Native (.deb/.rpm) | **Fully Supported** | Official Google repository builds |
| **Zen Browser** | Gecko (Firefox) | Flatpak, Tarball, AppImage | **Fully Supported** | Modern Firefox-based power-user browser |
| **Helium Browser** | WebEngine / Chromium | Native, Flatpak | **Fully Supported** | Lightweight privacy-focused browser |
| **Brave** | Chromium | Native, Flatpak | **Fully Supported** | Works with default shield settings |
| **Chromium** | Chromium | Native, Flatpak, Snap | **Fully Supported** | Open-source base browser |
| **Microsoft Edge** | Chromium | Native (.deb/.rpm) | **Fully Supported** | Linux release |
| **LibreWolf** | Gecko (Firefox) | Native, Flatpak, AppImage | **Fully Supported** | Hardened privacy browser |
| **Floorp / Waterfox** | Gecko (Firefox) | Native, Flatpak, AppImage | **Fully Supported** | Customizable Firefox forks |
| **Vivaldi / Opera** | Chromium | Native, Flatpak | **Fully Supported** | Feature-packed browsers |

### Flatpak & Snap Compatibility Note
Unlike direct smartcard token access (which is often blocked by container sandboxing), local HTTP/WebSocket loopback connections to `127.0.0.1` function out-of-the-box in Flatpak and Snap browsers without requiring any special sandbox permission tweaks (`--share=network` is enabled by default).

### No Browser Extension Required
Belfius's web application connects directly to the local bridge process via standard JavaScript `fetch()` and `WebSocket()` requests on localhost. **No browser extension or add-on is required.**

---

## Installation Tutorial

> **Binary Verification**:
> The official Belfius/OneSpan installer `digipass-nativebridge-installer.exe` has the following cryptographic hash:
> - **SHA-256**: `e3c70d7fb4e7f5c388d301dcf82aea6c9070691f020a831a10aa6e691893bd27`
> The installer script automatically verifies this hash before execution.

### Method A: Automated Installation (Recommended)

1. Clone this repository:
   ```bash
   git clone https://github.com/TinoZwino/belfius-digipass-nativebridge-linux-fix.git
   cd belfius-digipass-nativebridge-linux-fix
   ```

2. Make the installer executable:
   ```bash
   chmod +x install.sh uninstall.sh
   ```

3. Run the installer:
   ```bash
   ./install.sh
   ```

**What the installer does automatically:**
- [x] Protects against running with `sudo` (ensures user-level installation).
- [x] Detects distribution and verifies all required dependencies (`wine`, `gcc`/`clang`, `pcscd`, `libpcsclite`).
- [x] Dynamically finds the OneSpan NativeBridge executable anywhere in the Wine prefix.
- [x] Automatically verifies the SHA-256 checksum of `digipass-nativebridge-installer.exe`.
- [x] Compiles `pcsc_shim.c` into `~/.local/lib/libpcsc_wine_shim.so`.
- [x] Deletes the runaway watchdog monitor from Wine's startup registry.
- [x] Installs and starts the `digipass-nativebridge.service` user systemd service (or XDG desktop autostart on non-systemd distros).
- [x] Creates a convenient CLI command: `digipass-nativebridge`.

#### Upgrading to a New Version of NativeBridge
When Belfius releases a new version of `digipass-nativebridge-installer.exe`, simply drop the new installer into the directory and run:
```bash
./install.sh --upgrade
```

#### Custom Wine Prefix
To install into a dedicated or custom Wine prefix rather than `~/.wine`:
```bash
WINEPREFIX="$HOME/.local/share/wineprefixes/belfius" ./install.sh
```

---

### Method B: Manual Installation

If you prefer to perform the installation steps manually:

1. **Install the Windows application via Wine**:
   ```bash
   wine digipass-nativebridge-installer.exe
   ```
   Follow the on-screen installer wizard.

2. **Disable the buggy watchdog monitor in Wine registry**:
   ```bash
   wine reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v DigipassNativeBridge /f
   killall -q digipass-nativebridge-monitor.exe 2>/dev/null || true
   ```

3. **Compile the PC/SC Shim**:
   ```bash
   mkdir -p ~/.local/lib
   gcc -shared -fPIC -O2 -o ~/.local/lib/libpcsc_wine_shim.so pcsc_shim.c -ldl
   ```

4. **Create the systemd user service**:
   Find your bridge executable path:
   ```bash
   BRIDGE_DIR=$(find "$HOME/.wine/drive_c/users" -type d -name "NativeBridge" 2>/dev/null | head -n 1)
   ```
   Create `~/.config/systemd/user/digipass-nativebridge.service`:
   ```ini
   [Unit]
   Description=OneSpan DIGIPASS Native Bridge (Wine with PC/SC Shim)
   After=network.target

   [Service]
   Type=simple
   WorkingDirectory=%h/.wine/drive_c/users/YOUR_USER/AppData/Local/OneSpan/NativeBridge
   Environment="LD_PRELOAD=%h/.local/lib/libpcsc_wine_shim.so"
   Environment="WINEDEBUG=-all"
   ExecStart=/usr/bin/wine digipass-nativebridge.exe
   Restart=on-failure
   RestartSec=3s
   TimeoutStopSec=3s
   KillMode=mixed

   [Install]
   WantedBy=default.target
   ```
   *(Replace `YOUR_USER` with your Linux username)*

5. **Enable and start the service**:
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now digipass-nativebridge.service
   ```

---

## How to Log In to Belfius

1. Connect your **VASCO DIGIPASS 870** reader via USB to your computer.
2. Insert your **Belfius Bank Card** into the reader.
3. Open your favorite web browser (Google Chrome, Mozilla Firefox, Brave, Microsoft Edge, Zen, etc.).
4. Navigate to **[Belfius Aanmelden / Connexion](https://www.belfius.be/retail/nl/mijn-belfius/index.aspx?appkey=FEED)**.
5. Click **"Met USB-kabel"** (*With USB cable*).
6. The website will immediately detect the bridge and the card reader.
7. Follow the prompt on the physical DIGIPASS 870 screen, enter your PIN on the keypad, and press **OK**.
8. You are securely logged in to Belfius Direct Net!

---

## Service Management & Troubleshooting

### Check Status
```bash
systemctl --user status digipass-nativebridge.service
```
You should see `Active: active (running)` and `wine digipass-nativebridge.exe`.

### Check Network Ports
The bridge must be listening on TCP `127.0.0.1:42579` and `127.0.0.1:42580`:
```bash
ss -tulpn | grep 425
```

### Inspect Logs
The service logs directly to your user systemd journal without exposing world-readable files:
```bash
journalctl --user -u digipass-nativebridge.service -f
```
If you need to enable verbose smartcard shim debugging, set `PCSC_SHIM_DEBUG=1`:
```bash
PCSC_SHIM_DEBUG=1 digipass-nativebridge
```
Expected debug output during successful card detection:
```text
[PCSC_SHIM pid=...] SCardConnect(reader='VASCO DIGIPASS 870...', share=2, prefProto=3)
[PCSC_SHIM pid=...] SCardGetAttrib: Fixed SCARD_AUTOALLOCATE (0xffffffff -> -1)
[PCSC_SHIM pid=...] SCardGetAttrib(...) -> ret=0x0, out_len=20
[PCSC_SHIM pid=...]   autoallocated buffer ptr=0x...
```

### Restart Service
```bash
systemctl --user restart digipass-nativebridge.service
```

---

## Technical Upstream Notes (for WineHQ)

If Wine developers wish to address this in upstream Wine:
- In `dlls/winscard/unixlib.c` (and `dlls/winscard/winscard.c`), when `SCardGetAttrib` receives a `pcbAttrLen` parameter on 64-bit systems, Wine should check whether `*pcbAttrLen == 0xFFFFFFFF` (`SCARD_AUTOALLOCATE` in 32-bit Win32 API) and translate it to host `(unsigned long)-1` (`SCARD_AUTOALLOCATE` in Linux PC/SC Lite). Currently, passing `0x00000000FFFFFFFF` causes Linux `pcsclite` to fail with `SCARD_E_INSUFFICIENT_BUFFER`.

---

## Uninstallation

To cleanly remove the service, shim, and helpers:
```bash
./uninstall.sh
```
*(Your Wine prefix and banking files remain untouched).*

---

## License

This project is licensed under the [MIT License](LICENSE).

*Disclaimer: This repository is an independent open-source interoperability fix. It is not affiliated with, endorsed by, or associated with Belfius Bank SA/NV or OneSpan Inc.*
