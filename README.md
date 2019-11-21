# 841-OTA-Downgrader
Script that can be used to downgrade almost any supported 32-bit device to iOS 8.4.1

### Prerequisites:
- **Any jailbroken 32-bit iOS device**
- **OpenSSH** installed on iOS device
- **MTerminal** installed on iOS device (10.x users)
- iOS 7 Pangu users should install [this](http://apt.saurik.com/debs/io.pangu.axe7_0.3_iphoneos-arm.deb)
- iOS 8 Pangu users should install [this](http://apt.saurik.com/debs/io.pangu.xuanyuansword8_0.5_iphoneos-arm.deb)
- A Linux distro on PC (Tested on **Lubuntu 16.04 live USB** and Arch Linux)
- For VirtualBox users, add a New USB Filter in the VM settings
- For VMWare users, enable Autoconnect USB Devices
- The computer and device must be on the same network

### How to use:
- When the prerequisites are met, usage should be straightforward:
1. Download or `git clone` this repo
2. Open Terminal, cd to the directory where the scripts are located (eg. `cd /home/user/841-OTA-Downgrader`)
3. Run `chmod +x install.sh restore.sh`
4. Run `./install.sh`
5. Run `./restore.sh`
6. Follow instructions

### Tools used by this script:
- cURL
- [tsschecker](https://github.com/tihmstar/tsschecker)
- bsdiff (bspatch)
- [xpwntool](https://www.youtube.com/watch?v=fh0tB6fp0Sc)
- [kloader](https://www.youtube.com/watch?v=fh0tB6fp0Sc)
- [kloader5 (iOS 5)](http://www.pmbonneau.com/cydia/))
- [kloader_hgsp (iOS 10)](https://twitter.com/nyan_satan/status/945203180522045440)
- [futurerestore](https://github.com/tihmstar/futurerestore)

### Devices tested on:
- iPad3,3
- iPhone5,2

### Supported devices:

#### All iPad 2, iPad 3, iPad 4, iPod 5, iPhone 4S, and iPhone 5 devices (**NOT 5C**)

- iPad2,1
- iPad2,2
- iPad2,3
- iPad2,4
- iPad2,5
- iPad2,6
- iPad2,7
- iPad3,1
- iPad3,2
- iPad3,3
- iPad3,4
- iPad3,5
- iPad3,6
- iPod5,1
- iPhone4,1
- iPhone5,1
- iPhone5,2

