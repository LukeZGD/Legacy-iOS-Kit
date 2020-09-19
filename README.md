# iOS-OTA-Downgrader
### (formerly 32bit-OTA-Downgrader)
### Downgrade/restore and jailbreak iOS devices to signed OTA firmwares
- This downgrade script/tool supports **both Linux and macOS**
- iOS 8.4.1 and 6.1.3 downgrades have the option to jailbreak
  - For iOS 10.3.3, use [TotallyNotSpyware](https://totally-not.spyware.lol)
- **You do NOT need blobs to use this**, the script will get them for you
- **Please see the "Other notes" section below to serve as answers/solutions for frequent questions and issues**

## Supported devices:

- You can identify your device [here](https://ipsw.me/device-finder)
- **iOS 10.3.3** - A7 devices:
  - iPhone 5S
  - iPad Air 1
  - iPad mini 2 **except iPad4,6**
  - **iPad mini 3 is NOT supported**
- **iOS 8.4.1** - 32-bit devices:
  - iPhone 4S, iPhone 5
  - iPad 2, iPad 3, iPad mini 1
  - iPod 5th gen
  - **iPhone 5C is NOT Supported**
- **iOS 6.1.3**:
  - iPhone 4S
  - iPad 2 **except iPad2,4**

## Requirements:
- **A supported device in any iOS version:**
  - A 32-bit iOS device (**jailbreak needed**)
  - An A7 device (jailbreak not needed)
- An IPSW for the version you want to downgrade to
  - Links: [iOS 10.3.3](https://ipsw.me/10.3.3), [iOS 8.4.1](https://ipsw.me/8.4.1), [iOS 6.1.3](https://ipsw.me/6.1.3)
  - The script can also download it for you
- A **64-bit Linux install/live USB** or a supported **macOS** version
  - See supported OS versions and Linux distros below
  - A Linux live USB can be easily created with tools like [balenaEtcher](https://www.balena.io/etcher/) or [Rufus](https://rufus.ie/)
- All 32-bit users must install [OpenSSH](https://cydia.saurik.com/package/openssh/)
  - Users in iOS 10 must install [Dropbear (deb)](https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/Dropbear.deb) as well
  
<details>
  <summary>For Pangu 32-bit users:</summary>
  <ul><li>For 32-bit users using Pangu, install the latest untether for your iOS version <a href="https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/tag/untether">here</a></li></ul>
</details>

## How to use:
1. [Download iOS-OTA-Downgrader here](https://github.com/LukeZGD/iOS-OTA-Downgrader/archive/master.zip) and extract the zip archive
2. Plug in your iOS device
3. Open a Terminal window
4. `cd` to where the zip archive is extracted, and run `./restore.sh`
    - You can also drag `restore.sh` to the Terminal window and press ENTER
5. Select option to be used
6. Follow instructions

## Supported OS versions/distros:
- [Ubuntu 18.04](http://releases.ubuntu.com/bionic/) and Bionic-based distros
- [Ubuntu 20.04](http://releases.ubuntu.com/focal/) and Focal-based distros like [Linux Mint 20](https://www.linuxmint.com/)
- Ubuntu 20.10
- [Arch Linux](https://www.archlinux.org/) and Arch-based distros like [Manjaro](https://manjaro.org/)
- [Fedora 32 to 33](https://getfedora.org/)
- macOS 10.13 to 10.15

## Other notes:
- If something in the process does not work for you, try switching USB ports and/or cables (using a USB 2.0 port is recommended)
- This script will verify the IPSW SHA1sum before restoring
- For users having issues related to missing libraries or tools, re-install dependencies with `./restore.sh Install`
- For A7 devices:
  - Do not use USB-C to lightning cables as this can prevent a successful restore
  - checkm8 ipwndfu is unfortunately pretty unreliable, you may have to try multiple times (for Linux users I recommend trying in a live USB)
  - If the script can't find your device in pwnREC mode or gets stuck, you may have to start over
  - Other than the above there's not much else I can help regarding entering pwnDFU mode...
- For 32-bit devices:
  - To devices with baseband, this script will restore your device with the latest baseband (except when jailbreak is enabled)
  - This script has a workaround for the activation error on devices downgrading from iOS 10
  - This script can also be used to just enter kDFU mode for all supported devices
  - This script can also restore your device to other iOS versions with provided SHSH blobs
  - As alternatives to kloader/kDFU, checkm8 A5 or ipwndfu can also be used in DFU advanced menu
    - To enter DFU advanced menu, put your iOS device in DFU mode before running the script
  - This script can work on virtual machines, but I won't provide support for them
- For jailbreak option:
  - On iOS 8 downgrades, stashing is already enabled and `nosuid` is removed from `fstab`, so no need to install the "Stashing for #etasonJB" package
  - If you have problems with Cydia, remove the ultrasn0w repo and force-close Cydia, then try opening Cydia again
  - If you can't find Cydia in your home screen, try accessing Cydia through Safari with `cydia://`
  - Warning: If your device bootloops with EtasonJB, it may not work with the jailbreak option as well! (I think this applies to [8942](https://www.theiphonewiki.com/wiki/S5L8942)/[8945](https://www.theiphonewiki.com/wiki/S5L8945) users) If this happens, bootloop protection will trigger and you won't be able to open Cydia

## Tools and other stuff used by this script:
- cURL
- bspatch
- [ipwndfu](https://github.com/LukeZGD/ipwndfu)
- [iPwnder32](https://github.com/dora2-iOS/iPwnder32)
- [irecovery](https://github.com/LukeZGD/libirecovery)
- [libimobiledevice](https://github.com/libimobiledevice/libimobiledevice)
- [imobiledevice-net](https://github.com/libimobiledevice-win32/imobiledevice-net) (macOS)
- [idevicerestore](https://github.com/LukeZGD/idevicerestore)
- ipsw tool from OdysseusOTA/2
- python2
- [tsschecker](https://github.com/tihmstar/tsschecker)
- [futurerestore 152](http://api.tihmstar.net/builds/futurerestore/futurerestore-latest.zip) (32-bit)
- [futurerestore 251 (Linux)](https://github.com/LukeZGD/futurerestore) (A7)
- [futurerestore 245 (macOS)](https://github.com/MatthewPierson/Vieux/blob/master/resources/bin/futurerestore) (A7)
- [kloader](https://www.youtube.com/watch?v=fh0tB6fp0Sc)
- [kloader5 for iOS 5](https://mtmdev.org/pmbonneau-archive)
- [kloader_hgsp for iOS 10](https://twitter.com/nyan_satan/status/945203180522045440)
- [partial-zip](https://github.com/matteyeux/partial-zip)
- 32-bit iBSS patches are from [OdysseusOTA](https://www.youtube.com/watch?v=Wo7mGdMcjxw), [OdysseusOTA2](https://www.youtube.com/watch?v=fh0tB6fp0Sc), [alitek12](https://www.mediafire.com/folder/b1z64roy512wd/FirmwareBundles), [gjest](https://files.fm/u/fcbqqdnw)
- A7 iBSS and iBEC patches are from [MatthewPierson](https://github.com/MatthewPierson/iPhone-5s-OTA-Downgrade-Patches)
