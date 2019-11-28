# 32bit-OTA-Downgrader
- This script can be used to downgrade almost any supported 32-bit device to **iOS 8.4.1**
- iPhone 4S and some iPad 2 devices also have the option to downgrade to **iOS 6.1.3** (UNTESTED)
- This can also be used to enter pwnDFU mode for all supported devices

### Some notes:
- This script uses the futurerestore method for downgrading, NOT the Odysseus method nor modifying SystemVersion.plist
- This script will use an unmodified IPSW to restore
- This script only uses iBSS patches from bundles for entering pwnDFU mode, NOT for creating a custom IPSW

### Prerequisites:
- **Any jailbroken 32-bit iOS device** ([Phoenix](https://phoenixpwn.com/) for 9.3.5/9.3.6, [h3lix](https://h3lix.tihmstar.net/) for 10.3.3/10.3.4)
- **iOS [8.4.1](https://ipsw.me/8.4.1) or [6.1.3](https://ipsw.me/6.1.3) IPSW for your device**
- **A Linux install or live USB** (Tested on Lubuntu [16.04](http://cdimage.ubuntu.com/lubuntu/releases/16.04/release/), [18.04](http://cdimage.ubuntu.com/lubuntu/releases/18.04/release/), [Manjaro](https://manjaro.org/download/), and [Arch Linux](https://www.archlinux.org/)) (a live USB can be easily created with tools like [balenaEtcher](https://www.balena.io/etcher/) or [Rufus](https://rufus.ie/))
- **[OpenSSH](https://cydia.saurik.com/openssh.html)** installed on iOS device (
- **[MTerminal](http://cydia.saurik.com/package/com.officialscheduler.mterminal/)** installed on iOS device (10.x users only)
- iOS 7 Pangu users should install [this](http://apt.saurik.com/debs/io.pangu.axe7_0.3_iphoneos-arm.deb)
- iOS 8 Pangu users should install [this](http://apt.saurik.com/debs/io.pangu.xuanyuansword8_0.5_iphoneos-arm.deb)
- For VirtualBox users, add a New USB Filter in the VM settings
- For VMWare users, enable Autoconnect USB Devices
- The computer and device must be on the same network (for SSH)

### How to use:
- When the prerequisites are met, usage should be straightforward:
1. [Download](https://github.com/LukeZGD/32bit-OTA-Downgrader/archive/master.zip) or `git clone` this repo
2. Open Terminal, cd to the directory where the scripts are located (example: `cd /home/user/32bit-OTA-Downgrader`)
3. Run `chmod +x install.sh downgrader.sh`
4. Run `./install.sh`
5. Run `./downgrader.sh`
6. Select option to be used (8.4.1/6.1.3 downgrade or just enter pwnDFU mode)
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

- iBSS patches are from [OdysseusOTA](https://www.youtube.com/watch?v=Wo7mGdMcjxw), [OdysseusOTA2](https://www.youtube.com/watch?v=fh0tB6fp0Sc), [alitek12](https://www.mediafire.com/folder/b1z64roy512wd/FirmwareBundles), [gjest](https://files.fm/u/fcbqqdnw)

### Devices tested on:
- iPad3,3
- iPhone5,2

### Supported devices:

- (*) Also supports iOS 6.1.3 downgrade

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

#### iPhone 5C (**Enter pwnDFU mode ONLY, 8.4.1 OTA DOWNGRADING IS NOT SUPPORTED!)
- iPhone5,3**
- iPhone5,4**
