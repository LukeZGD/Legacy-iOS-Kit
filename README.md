# 32bit-OTA-Downgrader
- This script can be used to downgrade almost any supported 32-bit device to **iOS 8.4.1**
- iPhone 4S and some iPad 2 devices also have the option to downgrade to **iOS 6.1.3**
- This can also be used to enter pwnDFU mode for all supported devices

### Some other notes:
- **You do NOT need blobs to use this**, the script will save them for you
- **For iPhone 5C, 8.4.1 OTA DOWNGRADING IS NOT SUPPORTED!** Supports entering pwnDFU mode ONLY
- This script uses the futurerestore method for downgrading, NOT the Odysseus method nor modifying SystemVersion.plist
- This script will use a vanilla/unmodified IPSW to restore
- This script only uses iBSS patches from bundles for entering pwnDFU mode, NOT for creating a custom IPSW

### Prerequisites:
- **A supported jailbroken A5 or A6 iOS device on iOS 5 to 10** ([Phoenix](https://phoenixpwn.com/) for 9.3.5/9.3.6, [h3lix](https://h3lix.tihmstar.net/) for 10.3.3/10.3.4) (supported devices are listed below)
- **iOS [8.4.1](https://ipsw.me/8.4.1) or [6.1.3](https://ipsw.me/6.1.3) IPSW for your device**
- A **macOS** or **Linux install/live USB** (Tested on Lubuntu [16.04](http://cdimage.ubuntu.com/lubuntu/releases/16.04/release/), [18.04](http://cdimage.ubuntu.com/lubuntu/releases/18.04/release/), [Manjaro](https://manjaro.org/download/), and [Arch Linux](https://www.archlinux.org/)) (a live USB can be easily created with tools like [balenaEtcher](https://www.balena.io/etcher/) or [Rufus](https://rufus.ie/)) (macOS tested on 10.13 and 10.14)
- **[OpenSSH](https://cydia.saurik.com/openssh.html)** installed on iOS device
- **[MTerminal](http://cydia.saurik.com/package/com.officialscheduler.mterminal/)** installed on iOS device (10.x users only)
- iOS 7 Pangu users should install the [latest Pangu 7.1.x Untether](http://apt.saurik.com/debs/io.pangu.axe7_0.3_iphoneos-arm.deb)
- iOS 8 Pangu users should install the [latest Pangu 8.0-8.1.x Untether](http://apt.saurik.com/debs/io.pangu.xuanyuansword8_0.5_iphoneos-arm.deb)
- For VirtualBox users, add a New USB Filter in the VM settings
- For VMWare users, enable Autoconnect USB Devices
- The computer and device must be on the same network (for SSH)

### How to use:
- When the prerequisites are met, usage should be straightforward:
1. [Download](https://github.com/LukeZGD/32bit-OTA-Downgrader/archive/master.zip) or `git clone` this repo
2. Open Terminal, cd to the directory where the scripts are located (example: `cd /home/user/32bit-OTA-Downgrader`)
3. Run `chmod +x restore.sh`
4. Run `./restore.sh`
5. Select option to be used (8.4.1/6.1.3 downgrade or just enter pwnDFU mode)
6. Follow instructions

### Tools used by this script:
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

- iBSS patches are from [OdysseusOTA](https://www.youtube.com/watch?v=Wo7mGdMcjxw), [OdysseusOTA2](https://www.youtube.com/watch?v=fh0tB6fp0Sc), [alitek12](https://www.mediafire.com/folder/b1z64roy512wd/FirmwareBundles), [gjest](https://files.fm/u/fcbqqdnw)

### Devices tested on:
- iPad3,3
- iPhone5,2

### Supported devices:

- (*) Also supports iOS 6.1.3 downgrade
- (**) Entering pwnDFU mode ONLY, NOT 8.4.1 OTA DOWNGRADING

#### iPad 2
- iPad2,1* 
- iPad2,2*
- iPad2,3*
- iPad2,4

#### iPad mini 1
- iPad2,5
- iPad2,6
- iPad2,7

#### iPad 3
- iPad3,1
- iPad3,2
- iPad3,3

#### iPad 4
- iPad3,4
- iPad3,5
- iPad3,6

#### iPod touch 5
- iPod5,1

#### iPhone 4S
- iPhone4,1*

#### iPhone 5
- iPhone5,1
- iPhone5,2

#### iPhone 5C
- iPhone5,3**
- iPhone5,4**
