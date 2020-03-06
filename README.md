# 32bit-OTA-Downgrader
### Downgrade 32-bit iOS devices to iOS 8.4.1 or iOS 6.1.3 (see supported devices below first!)
- **Please see "Other notes" below to serve as answers for FAQs**

## Prerequisites:
- A supported 32-bit device **jailbroken** on any iOS version
- **iOS [8.4.1](https://ipsw.me/8.4.1) or [6.1.3](https://ipsw.me/6.1.3) IPSW** for your device (the script can also download it for you)
- A **Linux install/live USB** (see distros tested on below) (a live USB can be easily created with tools like [balenaEtcher](https://www.balena.io/etcher/) or [Rufus](https://rufus.ie/))
- **macOS** (tested on 10.13 and 10.14 only) should also work, but I won't be able to provide support when the script breaks
- iOS 7/8 Pangu users: Install the [latest Pangu 7.1.x Untether (deb)](http://apt.saurik.com/debs/io.pangu.axe7_0.3_iphoneos-arm.deb) or [latest Pangu 8.0-8.1.x Untether (deb)](http://apt.saurik.com/debs/io.pangu.xuanyuansword8_0.5_iphoneos-arm.deb)
- iOS 9 and below users: Install [OpenSSH](https://cydia.saurik.com/openssh.html); The computer and device must be on the same network for SSH to work
- iOS 10 users: Install [MTerminal](http://cydia.saurik.com/package/com.officialscheduler.mterminal/)

## How to use:
1. [Download](https://github.com/LukeZGD/32bit-OTA-Downgrader/archive/master.zip) or `git clone` this repo
2. Plug in your iOS device in normal mode
3. Open Terminal, cd to the directory where the script is located (example: `cd /home/user/32bit-OTA-Downgrader`)
4. Run `chmod +x restore.sh`
5. Run `./restore.sh`
6. Select option to be used (8.4.1/6.1.3 downgrade)
7. Follow instructions

## Supported devices (iOS 8.4.1 downgrade):

- All A5, A5X, A6, and A6X devices **except iPhone5,3 and 5,4 (iPhone 5C)** are supported

## Supported devices (iOS 6.1.3 downgrade):

- Only iPhone 4S and iPad 2 devices except iPad2,4 (iPad 2 Rev A) are supported

## Other notes:
- **You do NOT need blobs to use this**, the script will get them for you
- This script will also restore your device to the latest baseband (N/A to devices with no baseband)
- This script has a workaround for the activation error on iOS 10 devices
- This script uses the futurerestore method for downgrading, NOT the Odysseus method nor modifying SystemVersion.plist
- This script will use an unmodified IPSW to restore
- This script only uses iBSS patches from bundles for entering pwnDFU mode, NOT for creating a custom IPSW
- This script can also be used to enter kDFU mode for all supported devices
- This script can also be used to futurerestore to other iOS versions when provided with SHSH blobs
- This script should also work on virtual machines, but I won't provide support on them

## Linux distros tested on:
- [Lubuntu 16.04](http://cdimage.ubuntu.com/lubuntu/releases/16.04/release/) live USB
- [Lubuntu 18.04](http://cdimage.ubuntu.com/lubuntu/releases/18.04/release/) live USB
- [Arch Linux](https://www.archlinux.org/) full install
- [Manjaro](https://manjaro.org/) live USB and full install

## Tools used by this script:
- cURL
- bsdiff (bspatch)
- ideviceinfo
- ifuse
- [tsschecker](https://github.com/tihmstar/tsschecker)
- [futurerestore](https://github.com/tihmstar/futurerestore)
- [xpwntool](https://www.youtube.com/watch?v=fh0tB6fp0Sc)
- [kloader](https://www.youtube.com/watch?v=fh0tB6fp0Sc)
- [kloader5 (iOS 5)](http://www.pmbonneau.com/cydia/)
- [kloader_hgsp (iOS 10)](https://twitter.com/nyan_satan/status/945203180522045440)
- [partialZipBrowser](https://github.com/tihmstar/partialZipBrowser) (used on buildmanifestsaver.sh)
- python3 (http.server)

- iBSS patches are from [OdysseusOTA](https://www.youtube.com/watch?v=Wo7mGdMcjxw), [OdysseusOTA2](https://www.youtube.com/watch?v=fh0tB6fp0Sc), [alitek12](https://www.mediafire.com/folder/b1z64roy512wd/FirmwareBundles), [gjest](https://files.fm/u/fcbqqdnw)
