# Belfius DIGIPASS 870 on Linux (OneSpan NativeBridge + Wine Shim)

[![License: None](https://img.shields.io/badge/License-None%20(All%20Rights%20Reserved)-lightgrey.svg)](#license)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-orange.svg)](https://kernel.org)
[![Wine: 8.0+](https://img.shields.io/badge/Wine-8.0%2B%20%7C%209.0%2B%20%7C%2010.0%2B-blue.svg)](https://winehq.org)
[![Hardware: DIGIPASS 870](https://img.shields.io/badge/Hardware-VASCO%20%2F%20OneSpan%20870-brightgreen.svg)](https://www.onespan.com)
[![Authored by: AI](https://img.shields.io/badge/Authored%20by-AI%20Agent-purple.svg)](https://deepmind.google)

> [!WARNING]
> ### ⚠️ Disclaimer: 100% Developed by an AI Agent
> **I did not write this code, and I did not create this software.**
>
> This entire project—including the reverse-engineering analysis, the C interceptor shim (`pcsc_shim.c`), the automated installation scripts, the systemd services, and this documentation—was **100% developed by an AI agent** during an interactive debugging session.
>
> This is simply a personal workaround used to get a Belfius card reader working over USB on Linux. It is published publicly solely because it worked and might help other Linux users facing the exact same issue.
>
> * **Review Before Running**: Because this code was developed by an AI agent, please inspect the scripts and C source code before running them on your system.
> * **Use At Your Own Risk**: Provided strictly "as is", without warranty or guarantee of any kind.
> * **Not Affiliated**: This project is completely independent and is not affiliated with or endorsed by Belfius Bank SA/NV or OneSpan Inc.

A simple, automated fix to make the **VASCO / OneSpan DIGIPASS 870** card reader work on **Linux** for **Belfius Direct Net** (`https://www.belfius.be`) via USB cable.

---

## What This Does

To log in using a USB cable on Belfius online banking, Belfius uses a Windows program called **OneSpan NativeBridge**. Belfius does not make a Linux version. Running the Windows app in standard Wine fails because of a technical bug in Wine's smartcard translation layer (the website stays stuck on *"Insert your card"*).

This project fixes that bug with a tiny helper (`pcsc_shim.so`) and sets up everything automatically so your card reader and bank card work out-of-the-box in your web browser.

---

## Quick Start (Installation)

### 1. Install System Requirements

Run the command for your Linux distribution:

* **Fedora / RHEL:**
  ```bash
  sudo dnf install wine wine-smartcard pcsc-lite pcsc-lite-ccid gcc
  sudo systemctl enable --now pcscd
  ```

* **Ubuntu / Debian / Linux Mint / Pop!_OS:**
  ```bash
  sudo apt update && sudo apt install wine wine64 pcscd libpcsclite1 libccid build-essential
  sudo systemctl enable --now pcscd
  ```

* **Arch Linux / Manjaro:**
  ```bash
  sudo pacman -S wine pcsclite ccid gcc
  sudo systemctl enable --now pcscd
  ```

* **openSUSE:**
  ```bash
  sudo zypper install wine pcsc-lite pcsc-ccid gcc
  sudo systemctl enable --now pcscd
  ```

<details>
<summary><b>Click to see full OS compatibility table & details</b></summary>

| Distribution | Versions | Status | Package Manager Command |
| :--- | :--- | :---: | :--- |
| **Fedora** | 39, 40, 41+ | Fully Tested | `sudo dnf install wine wine-smartcard pcsc-lite pcsc-lite-ccid gcc` |
| **Ubuntu** | 22.04 LTS, 24.04 LTS, 24.10+ | Fully Supported | `sudo apt install wine wine64 pcscd libpcsclite1 libccid build-essential` |
| **Debian** | 12, 13, Sid | Fully Supported | `sudo apt install wine wine64 pcscd libpcsclite1 libccid build-essential` |
| **Linux Mint** | 21, 22+ | Fully Supported | `sudo apt install wine wine64 pcscd libpcsclite1 libccid build-essential` |
| **Pop!_OS / Zorin** | Current | Fully Supported | `sudo apt install wine wine64 pcscd libpcsclite1 libccid build-essential` |
| **Arch / Manjaro** | Rolling | Fully Supported | `sudo pacman -S wine pcsclite ccid gcc` |
| **openSUSE** | Tumbleweed, Leap | Fully Supported | `sudo zypper install wine pcsc-lite pcsc-ccid gcc` |
| **RHEL / Alma / Rocky** | 9.x, 10.x | Fully Supported | `sudo dnf install wine wine-smartcard pcsc-lite pcsc-lite-ccid gcc` |
| **Fedora Silverblue / Bazzite** | Immutable / Atomic | Supported | `rpm-ostree install wine-smartcard pcsc-lite pcsc-lite-ccid` |
| **Void / Alpine** | Non-systemd | Supported | Auto-configures `~/.config/autostart` desktop fallback |

> **Smartcard check**: You can verify your card reader is detected by running `pcsc_scan`. Insert your card and it will print `Card state: Card inserted`. Press `Ctrl+C` to quit.

</details>

---

### 2. Run the Installer

```bash
git clone https://github.com/TinoZwino/belfius-digipass-nativebridge-linux-fix.git
cd belfius-digipass-nativebridge-linux-fix
chmod +x install.sh uninstall.sh
./install.sh
```

**What the installer does automatically:**
- Checks your system packages and warns you if anything is missing.
- Runs the official Windows installer via Wine (if not already installed).
- Automatically verifies the installer hash (`SHA-256: e3c70d7fb4e7f5c388d301dcf82aea6c9070691f020a831a10aa6e691893bd27`).
- Compiles the lightweight shim (`pcsc_shim.c`) into `~/.local/lib/libpcsc_wine_shim.so`.
- Disables the buggy Windows monitor loop that leaks processes in Wine.
- Starts a background user service (`digipass-nativebridge.service`) that automatically runs on boot.

<details>
<summary><b>Click for advanced options (Upgrading or Custom Wine Prefix)</b></summary>

#### Upgrading to a New Version of NativeBridge
When Belfius releases an updated `digipass-nativebridge-installer.exe`, drop the new installer into the directory and run:
```bash
./install.sh --upgrade
```

#### Custom Wine Prefix
If you want to keep the banking bridge in an isolated Wine prefix instead of `~/.wine`:
```bash
WINEPREFIX="$HOME/.local/share/wineprefixes/belfius" ./install.sh
```

</details>

---

## How to Log In to Belfius

1. Connect your **DIGIPASS 870** reader via USB to your computer.
2. Insert your **Belfius Bank Card** into the reader.
3. Open your favorite web browser (Firefox, Chrome, Zen, Helium, Brave, Edge, etc.).
4. Go to **[Belfius Aanmelden](https://www.belfius.be/retail/nl/mijn-belfius/index.aspx?appkey=FEED)**.
5. Click **"Met USB-kabel"** (*With USB cable*).
6. **Important Browser Prompt**: If your browser shows a popup asking to access apps or open an application, click **Allow** (*Toestaan* / *Autoriser*).
7. The website will recognize your card reader immediately.
8. Follow the instructions on the card reader screen, enter your PIN on the keypad, and press **OK**. You are logged in!

<details>
<summary><b>Click for browser compatibility & permission details</b></summary>

All browsers (Firefox, Chrome, Zen, Helium, Brave, Edge, LibreWolf, Floorp, Vivaldi, Opera) are supported, whether installed natively, via Flatpak, or via Snap.

**Why the permission prompt appears:**
Belfius connects to the local bridge process on `127.0.0.1`. Modern web browsers protect users by asking for permission before a website can talk to local applications. You must click **"Allow"**, otherwise the browser blocks the connection.

No browser extension or add-on is required.

</details>

---

## Useful Commands

* **Check if the service is running:**
  ```bash
  systemctl --user status digipass-nativebridge.service
  ```
* **Restart the service:**
  ```bash
  systemctl --user restart digipass-nativebridge.service
  ```
* **View logs:**
  ```bash
  journalctl --user -u digipass-nativebridge.service -f
  ```
* **Uninstall:**
  ```bash
  ./uninstall.sh
  ```

---

<details>
<summary><b>Support for Other Banks & Services (Isabel 6, Crelan)</b></summary>

Although this fix was created for **Belfius**, the bridge program (`digipass-nativebridge.exe`) is standard commercial software from **OneSpan** (formerly VASCO Data Security).

Because this fix repairs the underlying smartcard connection in Wine, it also works for other services using OneSpan USB card readers:
* **Isabel 6**: The Belgian multi-banking portal used by businesses to access Belfius, BNP Paribas Fortis, ING, and KBC.
* **Crelan & others**: Other financial institutions issuing OneSpan DIGIPASS USB readers.

*(Note: Banks like KBC, Argenta, or ING retail that use offline card readers without a USB cable do not need any software at all).*

</details>

---

<details>
<summary><b>Technical Deep Dive: Why it fails by default in Wine</b></summary>

Three problems prevent the official Windows software from working out-of-the-box in Wine:

### 1. The 64-bit Wine `SCARD_AUTOALLOCATE` Bug
The bridge queries the smartcard's ATR string using Windows PC/SC:
```c
SCardGetAttrib(hCard, SCARD_ATTR_ATR_STRING, (LPBYTE)&pbAttr, &dwAttrLen);
```
In the Windows SDK, automatic buffer allocation uses:
```c
#define SCARD_AUTOALLOCATE (DWORD)(-1) /* 0xFFFFFFFF */
```
Under 64-bit Wine, Wine zero-extends the 32-bit value to 64 bits:
```c
(unsigned long)0xFFFFFFFF  ==>  0x00000000FFFFFFFF
```
However, Linux 64-bit PC/SC Lite defines:
```c
#define SCARD_AUTOALLOCATE ((unsigned long)-1) /* 0xFFFFFFFFFFFFFFFF */
```
Because `0x00000000FFFFFFFF != 0xFFFFFFFFFFFFFFFF`, Linux `libpcsclite` rejects the request with error `0x80100008` (`SCARD_E_INSUFFICIENT_BUFFER`). The card initialization fails with `"Internal error"`, and the browser stays stuck on *"Insert your card"*.

### 2. The Runaway Watchdog Process Loop
The installer adds `digipass-nativebridge-monitor.exe` to Wine's `Run` registry key. This watchdog checks if the bridge is running by calling `WTSEnumerateProcessesA`. Wine stubs this function to return 0. The watchdog assumes the bridge crashed and spawns a new bridge instance every second, eventually freezing the system with hundreds of Wine processes.

### 3. Flatpak Sandboxing
Running inside Flatpak sandboxes (like Bottles) blocks access to the host smartcard daemon socket (`/run/pcscd/pcscd.comm`).

</details>

---

<details>
<summary><b>Technical Deep Dive: How this fix works</b></summary>

1. **PC/SC ABI Shim (`pcsc_shim.c`)**:
   A small C library loaded via `LD_PRELOAD` intercepts `SCardGetAttrib`:
   ```c
   if (pcbAttrLen && *pcbAttrLen == 0xFFFFFFFFUL) {
       *pcbAttrLen = ((unsigned long)-1); /* Translates to 64-bit -1 */
   }
   ```
   `libpcsclite` now recognizes the allocation request, returns `SCARD_S_SUCCESS`, and card detection works. The shim also handles `SCARD_PROTOCOL_T0` fallback during reader negotiation.

2. **Watchdog Removal**:
   The installer removes `DigipassNativeBridge` from Wine's startup registry, stopping the process leak permanently.

3. **Managed Systemd User Service**:
   A standard user `systemd` unit runs the bridge cleanly in the background with auto-restart and zero overhead.

</details>

---

<details>
<summary><b>Method B: Manual Installation (Without the script)</b></summary>

1. **Install Windows app in Wine:**
   ```bash
   wine digipass-nativebridge-installer.exe
   ```
2. **Remove buggy monitor from Wine registry:**
   ```bash
   wine reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v DigipassNativeBridge /f
   killall -q digipass-nativebridge-monitor.exe 2>/dev/null || true
   ```
3. **Compile the shim:**
   ```bash
   mkdir -p ~/.local/lib
   gcc -Wall -Wextra -shared -fPIC -O2 -o ~/.local/lib/libpcsc_wine_shim.so pcsc_shim.c -ldl
   ```
4. **Create `~/.config/systemd/user/digipass-nativebridge.service`:**
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
5. **Enable and start:**
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now digipass-nativebridge.service
   ```

</details>

---

<details>
<summary><b>Notes for Wine Developers (Upstream Fix)</b></summary>

In `dlls/winscard/unixlib.c` and `winscard.c`, when `SCardGetAttrib` receives a `pcbAttrLen` parameter on 64-bit systems, Wine should check whether `*pcbAttrLen == 0xFFFFFFFF` (`SCARD_AUTOALLOCATE` in 32-bit Win32 API) and translate it to host `(unsigned long)-1` (`SCARD_AUTOALLOCATE` in Linux PC/SC Lite). Currently passing `0x00000000FFFFFFFF` causes Linux `pcsclite` to fail with `SCARD_E_INSUFFICIENT_BUFFER`.

</details>

---

## License

**No License / All Rights Reserved.**

This repository does **not** grant an open-source license. It is shared strictly as a personal workaround and technical troubleshooting reference:

- **No reuse, re-licensing, or redistribution**: You may not copy, sell, repackage, or distribute this repository or its contents without permission.
- **Third-Party Software**: The Windows installer (`digipass-nativebridge-installer.exe`), the OneSpan NativeBridge software, and the DIGIPASS trademarks are the exclusive property and copyright of **OneSpan Inc.** (formerly VASCO Data Security) and **Belfius Bank SA/NV**.
- **Disclaimer**: This repository is an independent personal interoperability fix. It is not affiliated with, endorsed by, or associated with Belfius Bank SA/NV or OneSpan Inc.
