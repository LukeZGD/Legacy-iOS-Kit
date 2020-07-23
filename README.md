# iOS-OTA-Downgrader
### (formerly 32bit-OTA-Downgrader)
### Downgrade/restore iOS devices to signed OTA firmwares
- **Please see "Other notes" below to serve as answers for FAQs**

## Supported devices:

- **iOS 10.3.3**: All A7 devices are supported **except iPad4,6 iPad4,7 iPad4,8 iPad4,9**
- **iOS 8.4.1**: All A5, A5X, A6, and A6X devices are supported **except iPad2,2 (iPad 2 GSM) iPhone5,3 and 5,4 (iPhone 5C)**
- **iOS 6.1.3**: Only iPhone 4S and iPad 2 devices are supported **except iPad2,2 (iPad 2 GSM) and iPad2,4 (iPad 2 Rev A)**

## Prerequisites:
- A supported device:
  - A 32-bit iOS device (any version, **jailbreak needed**)
  - An A7 device (any version, jailbreak not needed)
- An IPSW for the version you want to downgrade to (the script can also download it for you)
- A **macOS** or a **64-bit Linux install/live USB** (see distros tested on below) (a live USB can be easily created with tools like [balenaEtcher](https://www.balena.io/etcher/) or [Rufus](https://rufus.ie/))
- 32-bit users only:
  - iOS 7/8 Pangu users: Install the [latest Pangu 7.1.x Untether (deb)](http://apt.saurik.com/debs/io.pangu.axe7_0.3_iphoneos-arm.deb) or [latest Pangu 8.0-8.1.x Untether (deb)](http://apt.saurik.com/debs/io.pangu.xuanyuansword8_0.5_iphoneos-arm.deb)
  - iOS 9 and below users: Install [OpenSSH](https://cydia.saurik.com/package/openssh/); The computer and iOS device must be on the same network for SSH to work
  - iOS 10 users: Install [MTerminal](http://cydia.saurik.com/package/com.officialscheduler.mterminal/)
1. [Download](https://github.com/LukeZGD/iOS-OTA-Downgrader/archive/master.zip) or `git clone` this repo
2. Open Terminal, cd to the directory where the script is located (example: `cd /home/user/iOS-OTA-Downgrader`)
3. Run `chmod +x restore.sh`

## How to use:
1. Plug in your iOS device in:
  - Normal mode (32-bit)
  - Recovery or DFU mode (A7)
2. Run `./restore.sh`
3. Select option to be used
4. Follow instructions

## Other notes:
- **You do NOT need blobs to use this**, the script will get them for you
- This script will verify the IPSW with SHA1sum before restoring
- 32-bit only:
  - This script does not modify the IPSW
  - To devices with baseband, this script will restore your device with the latest baseband
  - This script has a workaround for the activation error on devices downgrading from iOS 10
  - This script uses futurerestore "Odysseus method" for downgrading (different from OdysseusOTA/2, which are deprecated)
  - This script only uses iBSS patches for entering kDFU mode
  - This script can also be used to just enter kDFU mode for all supported devices
  - This script can also be used to futurerestore to other iOS versions with provided SHSH blobs
  - This script can work on virtual machines, but I won't provide support for them

## OS versions/distros tested on:
- [Ubuntu 20.04](http://releases.ubuntu.com/focal/)
- [Arch Linux](https://www.archlinux.org/)
- [Manjaro](https://manjaro.org/) ([Testing branch](https://wiki.manjaro.org/index.php?title=Switching_Branches))
- [Fedora 32](https://getfedora.org/)
- macOS 10.13.6 High Sierra, 10.14.6 Mojave, 10.15.5 Catalina

## Tools and other stuff used by this script:
- cURL
- bspatch
- ifuse
- igetnonce
- ipwndfu
- libimobiledevice utilities
- python2
- python3
- [tsschecker](https://github.com/tihmstar/s0uthwest/tsschecker)
- [futurerestore 152 (Linux)](http://api.tihmstar.net/builds/futurerestore/futurerestore-latest.zip) (32-bit)
- [futurerestore 249 (Linux)](https://github.com/LukeZGD/futurerestore) (A7)
- [futurerestore 245 (macOS)](https://github.com/MatthewPierson/Vieux/blob/master/resources/bin/futurerestore)
- [xpwntool](https://www.youtube.com/watch?v=fh0tB6fp0Sc)
- [kloader](https://www.youtube.com/watch?v=fh0tB6fp0Sc)
- [kloader5 for iOS 5](https://mtmdev.org/pmbonneau-archive)
- [kloader_hgsp for iOS 10](https://twitter.com/nyan_satan/status/945203180522045440)
- [partialZipBrowser](https://github.com/tihmstar/partialZipBrowser/releases/tag/36)
- 32-bit iBSS patches are from [OdysseusOTA](https://www.youtube.com/watch?v=Wo7mGdMcjxw), [OdysseusOTA2](https://www.youtube.com/watch?v=fh0tB6fp0Sc), [alitek12](https://www.mediafire.com/folder/b1z64roy512wd/FirmwareBundles), [gjest](https://files.fm/u/fcbqqdnw)
- A7 iBSS and iBEC patches are from [MatthewPierson](https://github.com/MatthewPierson/iPhone-5s-OTA-Downgrade-Patches)
