# 32bit-OTA-Downgrader
- This script can be used to downgrade almost any supported 32-bit device to **iOS 8.4.1**
- This can also be used to enter pwnDFU mode for all devices
- iPhone 4S and some iPad 2 devices also have the option to downgrade to **iOS 6.1.3** (UNTESTED) (iPad 2,3 users have to enter pwnDFU mode manually with tools like [kDFUApp](https://twitter.com/tihmstar/status/661302215928381441?lang=en))

### Prerequisites:
- **Any jailbroken 32-bit iOS device**
- **OpenSSH** installed on iOS device
- **MTerminal** installed on iOS device (10.x users)
- iOS 7 Pangu users should install [this](http://apt.saurik.com/debs/io.pangu.axe7_0.3_iphoneos-arm.deb)
- iOS 8 Pangu users should install [this](http://apt.saurik.com/debs/io.pangu.xuanyuansword8_0.5_iphoneos-arm.deb)
- A Linux install or live USB (Tested on Lubuntu **16.04**, Manjaro, and Arch Linux) (macOS may also work with dependencies installed)
- For VirtualBox users, add a New USB Filter in the VM settings
- For VMWare users, enable Autoconnect USB Devices
- The computer and device must be on the same network (for SSH)

### How to use:
- When the prerequisites are met, usage should be straightforward:
1. Download or `git clone` this repo
2. Open Terminal, cd to the directory where the scripts are located (eg. `cd /home/user/32bit-OTA-Downgrader`)
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


- iBSS patches are from [OdysseusOTA2](https://www.youtube.com/watch?v=fh0tB6fp0Sc), [alitek12](https://www.mediafire.com/folder/b1z64roy512wd/FirmwareBundles), [gjest](https://files.fm/u/fcbqqdnw)

### Devices tested on:
- iPad3,3
- iPhone5,2

### Supported devices:

- (*) Also supports iOS 6.1.3 downgrade
- (**) Enter pwnDFU mode ONLY

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

