# 32bit-OTA-Downgrader
### Downgrade/restore 32-bit iOS devices to iOS 8.4.1 or iOS 6.1.3
- **Please see "Other notes" below to serve as answers for FAQs**

## Supported devices:

- **iOS 8.4.1**: All A5, A5X, A6, and A6X devices are supported **except iPhone5,3 and 5,4 (iPhone 5C)**
- **iOS 6.1.3**: Only iPhone 4S and iPad 2 devices are supported **except iPad2,4 (iPad 2 Rev A)**

## Prerequisites:
- A supported 32-bit iOS device **jailbroken** on any version
- **iOS [8.4.1](https://ipsw.me/8.4.1) or [6.1.3](https://ipsw.me/6.1.3) IPSW** for your device (the script can also download it for you)
- A **macOS** or a **64-bit Linux install/live USB** (see distros tested on below) (a live USB can be easily created with tools like [balenaEtcher](https://www.balena.io/etcher/) or [Rufus](https://rufus.ie/))
- iOS 7/8 Pangu users: Install the [latest Pangu 7.1.x Untether (deb)](http://apt.saurik.com/debs/io.pangu.axe7_0.3_iphoneos-arm.deb) or [latest Pangu 8.0-8.1.x Untether (deb)](http://apt.saurik.com/debs/io.pangu.xuanyuansword8_0.5_iphoneos-arm.deb)
- iOS 9 and below users: Install [OpenSSH](https://cydia.saurik.com/package/openssh/); The computer and iOS device must be on the same network for SSH to work
- iOS 10 users: Install [MTerminal](http://cydia.saurik.com/package/com.officialscheduler.mterminal/)

## How to use:
1. [Download](https://github.com/LukeZGD/32bit-OTA-Downgrader/archive/master.zip) or `git clone` this repo
2. Plug in your iOS device in normal mode
3. Open Terminal, cd to the directory where the script is located (example: `cd /home/user/32bit-OTA-Downgrader`)
4. Run `chmod +x restore.sh`
5. Run `./restore.sh`
6. Select option to be used
7. Follow instructions

## Other notes:
- **You do NOT need blobs to use this**, the script will get them for you
- To devices with baseband, this script will restore your device with the latest baseband
- This script has a workaround for the activation error on devices downgrading from iOS 10
- This script uses futurerestore "Odysseus method" for downgrading (different from OdysseusOTA/2, which are deprecated)
- This script does not modify the IPSW and will verify it with SHA1sum before restoring
- This script only uses iBSS patches for entering kDFU mode
- This script can also be used to just enter kDFU mode for all supported devices
- This script can also be used to futurerestore to other iOS versions with provided SHSH blobs
- This script can also work on virtual machines, but I won't provide support for them

## OS versions/distros tested on:
- [Lubuntu 16.04](http://cdimage.ubuntu.com/lubuntu/releases/16.04/release/) live USB
- [Lubuntu 18.04](http://cdimage.ubuntu.com/lubuntu/releases/18.04/release/) live USB
- [Arch Linux](https://www.archlinux.org/) full install
- [Manjaro](https://manjaro.org/) live USB and full install
- macOS 10.14.6 Mojave

## Tools and other stuff used by this script:
- cURL
- bspatch
- ideviceinfo
- ifuse
- python3 (http.server)
- [tsschecker](https://github.com/tihmstar/tsschecker/releases/tag/v212)
- [futurerestore](http://api.tihmstar.net/builds/futurerestore/futurerestore-latest.zip)
- [xpwntool](https://www.youtube.com/watch?v=fh0tB6fp0Sc)
- [kloader](https://www.youtube.com/watch?v=fh0tB6fp0Sc)
- [kloader5 for iOS 5](https://mtmdev.org/pmbonneau-archive)
- [kloader_hgsp for iOS 10](https://twitter.com/nyan_satan/status/945203180522045440)
- [partialZipBrowser](https://github.com/tihmstar/partialZipBrowser/releases/tag/36)
- iBSS patches are from [OdysseusOTA](https://www.youtube.com/watch?v=Wo7mGdMcjxw), [OdysseusOTA2](https://www.youtube.com/watch?v=fh0tB6fp0Sc), [alitek12](https://www.mediafire.com/folder/b1z64roy512wd/FirmwareBundles), [gjest](https://files.fm/u/fcbqqdnw)
