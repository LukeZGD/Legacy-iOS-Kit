# SECTION 0 - Things to note before you begin
- Some of the sections and steps will be separated depending on your platform and device.
- Make sure that your OS version/distro and your iOS device are compatible before proceeding.
- Make sure to have at least 10 GB of free space.
- **For A7 devices, Windows support is limited.** Read [TROUBLESHOOTING.md](https://github.com/LukeZGD/iOS-OTA-Downgrader/blob/master/TROUBLESHOOTING.md) for more details.
- **Restoring to other versions with SHSH blobs is not supported on Windows.**

# SECTION 1.1 - Setup for PC/Mac

## Windows
1. Your installation of Windows must be **64-bit**. Windows 8.1 and 10 are supported, but Windows 7 may also work.
1. Install [iTunes](https://www.apple.com/itunes/download/win64), version 12.10.11 or newer. Make sure to not install the Microsoft Store version.
1. Install [MSYS2](https://www.msys2.org/#installation), follow steps 1 to 4 only. In step 4, untick "Run MSYS2 64-bit now" before clicking Finish.
1. [Download iOS-OTA-Downgrader](https://api.github.com/repos/LukeZGD/iOS-OTA-Downgrader/zipball) and extract the zip archive.
1. Go to where the extracted files are located, and run `restore.cmd`
    - It may only show up as `restore`. If this is the case, run the one that has the gears icon. I recommend to [make Windows show file extensions](https://www.howtogeek.com/205086/beginner-how-to-make-windows-show-file-extensions/) to avoid confusion.
1. On its first run, it will download and install dependencies. This will take some time depending on your Internet connection. When it's done, proceed to the next section.

## macOS/Linux
1. [Download iOS-OTA-Downgrader](https://api.github.com/repos/LukeZGD/iOS-OTA-Downgrader/zipball) and extract the zip archive. (it will be extracted automatically if downloaded from Safari)
1. Open a Terminal window. (for macOS, [here's how](https://support.apple.com/guide/terminal/apd5265185d-f365-44cb-8b09-71a064a42125/mac))
1. Go to where the extracted files are located, and drag `restore.sh` to the Terminal window, and press Enter.
1. On its first run, it will download and install dependencies. This will take some time depending on your Internet connection. When it's done, proceed to the next section.

# SECTION 1.2 - Setup for iOS device

## 32-bit devices
1. [Jailbreak your device.](https://www.reddit.com/r/LegacyJailbreak/comments/jhjam8/tutorial_how_to_sideload_apps_ipas_used_for/)
    - For alternatives, the DFU advanced menu can also be used. Read [TROUBLESHOOTING.md](https://github.com/LukeZGD/iOS-OTA-Downgrader/blob/master/TROUBLESHOOTING.md) for more details
1. Open Cydia, and wait for sources to refresh. When it asks to upgrade, tap Ignore.
1. Go to Search, and search for OpenSSH.
1. When OpenSSH shows up, tap and install it.
    - If you have an iPhone 5 or an iPad 4 on iOS 10, do the additional steps below. Otherwise, proceed to the next section.
1. Go to Sources, tap Edit at the top right, then tap Add at the top left.
1. Add this repository: https://lukezgd.github.io/repo/
1. After the repo is added, go to Search, and search for Dropbear.
1. When Dropbear shows up, tap and install it. When it's done, proceed to the next section.

## A7 devices
1. No prior setup is needed. Proceed to the next section.

# SECTION 2 - Downgrading the device

## 32-bit devices
1. Connect your iOS device to your PC/Mac. Make sure to also trust the computer by selecting "Trust" at the pop-up.
    - **Windows/macOS**: Double-check if the device is being detected by iTunes/Finder.
1. Run the script.
    - **Windows**: Go to where the extracted files are located, and run `restore.cmd` (the one that has the gears icon)
    - **macOS/Linux**: Go to where the extracted files are located, and drag `restore.sh` to the Terminal window, and press Enter/Return.
1. When the main menu shows up, type '1' and press Enter/Return.
1. Select your target version and options, and follow the instructions that the script will give you.
1. After the downgrade process, your device will be successfully in your selected target version.
    - **Windows**: The restore process may give out an error on your first try. If this happens, follow the steps in [TROUBLESHOOTING.md](https://github.com/LukeZGD/iOS-OTA-Downgrader/blob/master/TROUBLESHOOTING.md)

## A7 devices
- Connect your iOS device to your PC/Mac.
- Run the script.
    - **Windows**: Take note of the limited support on Windows before proceeding. More details in [TROUBLESHOOTING.md](https://github.com/LukeZGD/iOS-OTA-Downgrader/blob/master/TROUBLESHOOTING.md)
    - **macOS/Linux**: Go to where the extracted files are located, and drag `restore.sh` to the Terminal window, and press Enter/Return.
- Let the script put the device to recovery mode, and follow the steps to enter DFU mode.
- When in DFU mode, wait for the script will put the device to pwnDFU mode.
    - **Linux**: Entering pwnDFU mode can fail a lot on Linux. Read [TROUBLESHOOTING.md](https://github.com/LukeZGD/iOS-OTA-Downgrader/blob/master/TROUBLESHOOTING.md) for more details
- When the main menu shows up, type '1' and press Enter/Return.
- Select your target version and options, and follow the instructions that the script will give you.
- After the downgrade process, your device will be successfully in iOS 10.3.3.
