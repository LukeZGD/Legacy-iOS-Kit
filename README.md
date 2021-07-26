# iOS-OTA-Downgrader
### Downgrade/restore and jailbreak iOS devices to signed OTA firmwares
- **Linux and macOS** are supported
  - Windows users can create a Linux live USB (see Requirements)
- iOS 8.4.1 and 6.1.3 downgrades have the option to **jailbreak** the install
  - For iOS 10.3.3, use [TotallyNotSpyware](https://totally-not.spyware.lol) or [sockH3lix](https://github.com/SongXiaoXi/sockH3lix) to jailbreak
- **You do NOT need blobs to use this**, the script will get them for you
- This script can also restore your device to other iOS versions that you have SHSH blobs for (32-bit devices only, listed under Supported devices)
- **Please read the "Other notes" section for tips, frequent questions, and troubleshooting**

## Supported devices:

- You can identify your device [here](https://ipsw.me/device-finder)
- **iPhone 5C and iPad mini 3 devices are NOT supported** (OTA versions for them are not signed)
- iPhone 5C can still be restored to versions that you have SHSH blobs for

<table>
    <thead>
        <tr>
            <th>Target Version</th>
            <th>Supported Devices</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td rowspan=4>iOS 10.3.3</td>
            <td><b>A7 devices:</b></td>
        </tr>
        <tr><td>iPhone 5S</td></tr>
        <tr><td>iPad Air 1</td></tr>
        <tr><td>iPad mini 2 (except iPad4,6)</td></tr>
        <tr>
            <td rowspan=6>iOS 8.4.1</td>
            <td><b>32-bit devices:</b></td>
        </tr>
        <tr><td>iPhone 4S</td></tr>
        <tr><td>iPhone 5</td></tr>
        <tr><td>iPad 2, iPad 3, iPad 4</td></tr>
        <tr><td>iPad mini 1</td></tr>
        <tr><td>iPod touch 5</td></tr>
        <tr>
            <td rowspan=2>iOS 6.1.3</td>
            <td>iPhone 4S</td>
        </tr>
        <tr><td>iPad 2 (except iPad2,4)</td></tr>
    </tbody>
</table>

## Requirements:
- **A supported device in any iOS version (listed above)**
- The IPSW firmware for the version you want to downgrade to
  - Links: [iOS 10.3.3](https://ipsw.me/10.3.3), [iOS 8.4.1](https://ipsw.me/8.4.1), [iOS 6.1.3](https://ipsw.me/6.1.3) (ignore the signing statuses in the site)
  - The script can also download it for you
- A **64-bit Linux install/live USB** or a supported **macOS** version
  - See supported OS versions and Linux distros below
  - A Linux live USB can be easily created with tools like [Ventoy](https://www.ventoy.net/en/index.html)
- **32-bit devices** - The device needs to be put in kDFU/pwnDFU mode as part of the process. There are a few options:
  - Normal method - **jailbreak is required**. Users must install [OpenSSH](https://cydia.saurik.com/package/openssh/). Users in iOS 10 (A6/A6X) must also install Dropbear from my [Cydia repo](https://lukezgd.github.io/repo/)
  - DFU method - for alternatives, the DFU advanced menu can also be used. See "Other notes" for more details
- **A7 devices** - jailbreak is not required. The script will assist in helping the user put the device to pwnDFU mode

<details>
  <summary>For Pangu 32-bit users:</summary>
  <ul><li>For 32-bit users using Pangu and normal method, install the latest untether for your iOS version <a href="https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/tag/untether">here</a></li></ul>
</details>

## Usage:
1. [Download iOS-OTA-Downgrader here](https://github.com/LukeZGD/iOS-OTA-Downgrader/archive/master.zip) and extract the zip archive
2. Plug in your iOS device
3. Open a Terminal window
4. `cd` to where the zip archive is extracted, and run `./restore.sh`
    - You can also drag `restore.sh` to the Terminal window and press Enter/Return
5. Select options to be used
6. Follow instructions

## Supported OS versions/distros:
- [**Ubuntu**](https://ubuntu.com/) 20.04 and newer, and Ubuntu-based distros like [Linux Mint](https://www.linuxmint.com/)
- [**Arch Linux**](https://www.archlinux.org/) and Arch-based distros like [EndeavourOS](https://endeavouros.com/)
- [**Fedora**](https://getfedora.org/) 33 and newer
- [**Debian**](https://www.debian.org/) 11 Bullseye, Testing and Unstable
- [**openSUSE**](https://www.opensuse.org/) Tumbleweed and Leap 15.3
- **macOS** 10.13 and newer

## Other notes:
- **If something in the process does not work for you:** try unplugging/replugging the device, switching between different USB ports/cables, also try USB 2.0 ports
- **IPSW file integrity** will be verified before restoring and/or creating custom IPSW (if custom IPSW is already created, this will be skipped)
- **For users having issues with missing libraries/tools:** Re-install dependencies with `./restore.sh Install`
  - Alternatively, delete the `libimobiledevice` folder in `resources` then run the script again
- **For A7 devices:**
  - Do not use USB-C to lightning cables as this can prevent a successful restore
  - ipwndfu is unfortunately very unreliable on Linux, you may have to try multiple times (Linux users may also try in a live USB)
  - If the script cannot find your device in pwnREC mode or gets stuck, you may have to start over by [force restarting](https://support.apple.com/en-ph/guide/iphone/iph8903c3ee6/ios) and re-entering recovery/DFU mode
  - macOS users may have to install libimobiledevice and libirecovery from [Homebrew](https://brew.sh/) with this command: `brew install libimobiledevice libirecovery`
    - The script will detect this automatically and will use the Homebrew versions of the tools
  - Use an Intel or Apple Silicon PC/Mac as entering pwnDFU (checkm8) may be a lot more unreliable on AMD devices
  - Other than the above, unfortunately there is not much else I can do to help regarding entering pwnDFU mode.
- **For 32-bit devices:**
  - To make sure that SSH is successful, try these steps: Reinstall OpenSSH/Dropbear, reboot and rejailbreak, then reinstall them again
  - To devices with baseband, this script will restore your device with the latest baseband (except when jailbreak is enabled, and on iPhone5,1 as there are reported issues)
  - This script can also be used to just enter kDFU mode for all supported devices
  - This script can work on virtual machines, but I will not provide support for them
  - If you want to use other manually saved blobs for 6.1.3/8.4.1, create a folder named `saved`, then within it create another folder named `shsh`. You can then put your blob inside that folder.
    - The naming of the blob should be: `(ECID in Decimal)_(ProductType)_(Version)-(BuildVer).shsh(2)`
    - Example with path: `saved/shsh/123456789012_iPad2,1_8.4.1-12H321.shsh`
- **For DFU advanced menu:**
  - To enter DFU advanced menu, put your iOS device in recovery (A6 only), normal DFU (also A6 only), kDFU, or pwnDFU mode before running the script
  - There are three options that can be used for the DFU advanced menu
  - Select the "kDFU mode" option if your device is already in kDFU mode beforehand. Example of this is using kDFUApp by tihmstar; kDFUApp can also be installed from my repo
  - For A6/A6X devices, "DFU mode (A6)" option can be used. This will use ipwndfu (or iPwnder32 for Mac) to put your device in pwnDFU mode, send pwned iBSS, and proceed with the downgrade/restore
  - For A5/A5X devices, "pwnDFU mode (A5)" option can be used, BUT ONLY IF the device is put in pwnDFU mode beforehand, with an Arduino and USB Host Shield ([checkm8-a5](https://github.com/synackuk/checkm8-a5))
- **For the jailbreak option (iOS 6.1.3 and 8.4.1):**
  - If you have problems with Cydia, remove the ultrasn0w repo and close Cydia using the app switcher, then try opening Cydia again
  - If you cannot find Cydia in your home screen, try accessing Cydia through Safari with `cydia://` and install "Jailbreak App Icons Fix" package from my Cydia repo
- **For the jailbreak option (iOS 8.4.1 only):**
  - Stashing is already enabled and `nosuid` is removed from `fstab`, so there is no need to install "Stashing for #etasonJB" package
- **For users with A5 Rev A ([8942](https://www.theiphonewiki.com/wiki/S5L8942)) and A5X ([8945](https://www.theiphonewiki.com/wiki/S5L8945)) devices:**
  - **A5 Rev A devices:** iPad2,4, iPad mini 1, iPod touch 5
  - **A5X devices:** iPad 3
  - The jailbreak option **might not work** on A5 Rev A devices. (see issue [#70](https://github.com/LukeZGD/iOS-OTA-Downgrader/issues/70)) The script will warn you if you enable the jailbreak option on one of these devices
  - For users that downgraded **without** jailbreak option, and have manually jailbroken with the EtasonJB app, it is recommended to install "EtasonJB Disable Bootloop Protection" from my Cydia repo
  - For users that downgraded **with** the jailbreak option, and to users that have installed "EtasonJB Disable Bootloop Protection", your device might take a very long time to boot, possibly 20 minutes or more
- **My Cydia repo**: https://lukezgd.github.io/repo/ - for installing Dropbear, Jailbreak App Icons Fix, EtasonJB Disable Bootloop Protection, kDFUApp

## Tools and other stuff used by this script:
- cURL
- bspatch
- [ipwndfu](https://github.com/LukeZGD/ipwndfu)
- [iPwnder32](https://github.com/dora2-iOS/iPwnder32)
- [irecovery](https://github.com/libimobiledevice/libirecovery)
- [libimobiledevice](https://github.com/libimobiledevice/libimobiledevice)
- [imobiledevice-net](https://github.com/libimobiledevice-win32/imobiledevice-net) (macOS)
- [idevicerestore](https://github.com/LukeeGD/idevicerestore)
- ipsw tool from [xpwn](https://github.com/LukeeGD/xpwn) (OdysseusOTA/2)
- Python 2 (for ipwndfu, rmsigchks, SimpleHTTPServer)
- [tsschecker](https://github.com/tihmstar/tsschecker)
- [futurerestore](http://api.tihmstar.net/builds/futurerestore/futurerestore-latest.zip) used for 32-bit devices
- [futurerestore](https://github.com/m1stadev/futurerestore) used for A7 devices
- [kloader](https://www.youtube.com/watch?v=fh0tB6fp0Sc)
- [kloader5 for iOS 5](https://www.pmbonneau.com/cydia/com.pmbonneau.kloader5_1.2_iphoneos-arm.deb)
- [kloader_hgsp for iOS 10](https://twitter.com/nyan_satan/status/945203180522045440)
- [partial-zip](https://github.com/matteyeux/partial-zip)
- 32-bit bundles are from [OdysseusOTA](https://www.youtube.com/watch?v=Wo7mGdMcjxw), [OdysseusOTA2](https://www.youtube.com/watch?v=fh0tB6fp0Sc), [alitek12](https://www.mediafire.com/folder/b1z64roy512wd/FirmwareBundles), [gjest](https://www.reddit.com/r/jailbreak/comments/6yrzzj/release_firmware_bundles_for_ios_841_ipad21234567/)
- A7 patches are from [MatthewPierson](https://github.com/MatthewPierson/iPhone-5s-OTA-Downgrade-Patches)
- [EtasonJB](https://www.theiphonewiki.com/wiki/EtasonJB)
- [p0sixspwn](https://www.theiphonewiki.com/wiki/p0sixspwn)
