# Native Wireless CarPlay (WCP) Mod for Mazda CMU150

Enable native Wireless Apple CarPlay on compatible Mazda CMU150 hardware originally supporting wired CarPlay only.

## Compatibility

- **Hardware:** Mazda CMU150
- **Firmware:** `V74.00.324`
- **Status:** Successfully tested

## How It Works

The installer enables Wireless CarPlay by modifying three CMU components:

- **`get_board_type.sh`** — Spoofs the hardware detection result based on the calling process to enable WCP behavior.
- **`sm_WCP.conf`** — Adjusts `jciLDS` and `jcinavi` service settings, including GPS arguments and board reset behavior.
- **`autostart`** — Prevents the startup process from creating `ublox.txt`.

The installer backs up the original files before applying changes, validates the modifications, and reboots the CMU after installation. An uninstaller is included to restore the original files from backups.

## Requirements

- Firmware **74.00.324**
- USB flash drive **32 GB or smaller**, formatted as **FAT32**

## Installation / Uninstallation

1. Extract the ZIP archive and copy all files to the **root directory** of the USB drive.
2. Safely eject the drive and plug it into your Mazda.
3. Wait a few seconds for the installer dialog to appear.
4. Follow the on-screen prompts to install or uninstall the mod.
5. Wait for the CMU to reboot automatically.

**Do not remove the USB drive or interrupt the process while it is running.**

## Disclaimer

This is an unofficial modification. Use it at your own risk. Back up original files before proceeding. Compatibility with other hardware or firmware versions is not verified.

## License

[MIT License](LICENSE)

Copyright (c) 2026 Kenatia
