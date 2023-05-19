# Legacy iOS Kit

- (formerly iOS-OTA-Downgrader)
- **A multi-purpose script to save SHSH blobs, downgrade/restore, and jailbreak supported legacy iOS devices**
- **Linux, macOS, and Windows** are supported
    - Windows usage is not recommended
- **Read the ["How to Use" wiki page](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/How-to-Use) for usage instructions**
- **Read the ["Troubleshooting" wiki page](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Troubleshooting) for tips, frequent questions, and troubleshooting**

## Features
- Restore to iOS 8.4.1 or 6.1.3 on supported 32-bit devices **(OTA signed)**
- Restore iPhone 4 GSM (iPhone3,1) to unsigned iOS versions **(powdersn0w)**
- Restore to iOS 10.3.3 on supported A7 devices **(OTA signed)**
- Option to **jailbreak** iOS 6.1.3 and 8.4.1 restores
- Restore to unsigned iOS versions **with SHSH blobs**
- Restore to unsigned iOS versions **with iOS 7.1.x blobs (powdersn0w)**
    - Device support is limited, see below
- The latest baseband will be used for 32-bit devices if applicable
- Place device to pwned iBSS/kDFU mode for 32-bit devices
- Clear NVRAM for devices that support powdersn0w
- Restore iPhone 4 to iOS 7.1.2 with the option to jailbreak
- Restore supported devices to their latest iOS version
- Save onboard and Cydia SHSH blobs for 32-bit devices
- Boot SSH Ramdisk on supported 32-bit devices
- Pwning supported iOS devices using limera1n or checkm8 with iPwnder/gaster
- Device activation using ideviceactivation on Linux

## Supported devices
- [Identify your device here](https://ipsw.me/device-finder)
- **iPhone 5C and iPad mini 3 devices are NOT supported by OTA downgrades**
    - These devices still support restoring to other iOS versions with SHSH blobs, see below
- See the table below for OTA downgrading support:

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

- Restoring with SHSH blobs and using SSH Ramdisks are supported on the following devices:
    - Supports most 32-bit devices (iOS 3 to 10, version range depends on device)
    - iPhone 3GS, 4, 4S, 5, 5C
    - iPad 1, 2, 3, 4, mini 1
    - iPod touch 3, 4, 5
- Restoring with SHSH blobs is also supported on most A7/A8 devices:
    - See [SEP/BB Compatibility Chart](https://docs.google.com/spreadsheets/d/1Mb1UNm6g3yvdQD67M413GYSaJ4uoNhLgpkc7YKi3LBs/edit#gid=1191207636) for iOS versions
    - iPhone 5S, 6, 6 Plus
    - iPad Air 1, mini 2, mini 3
    - iPod touch 6
- Restoring with powdersn0w is supported on the following devices:
    - iPhone 4 GSM - targets iOS 4.3 to 6.1.3
    - iPhone 4S, iPhone 5 (not 5C), iPad 2 Rev A, iPod 5th generation - targets iOS 5.0 to 6.1.3, 8.0 to 9.3.5
    - Using powdersn0w requires iOS 7.1.x blobs for your device

## Supported OS versions/distros

#### Supported architectures: x86_64, arm64, armhf

- [**Ubuntu**](https://ubuntu.com/) 22.04 and newer, and Ubuntu-based distros like [Linux Mint](https://www.linuxmint.com/)
- [**Arch Linux**](https://www.archlinux.org/) and Arch-based distros like [EndeavourOS](https://endeavouros.com/)
- [**Fedora**](https://getfedora.org/) 36 and newer
- [**Debian**](https://www.debian.org/) 12 Bookworm and newer, Sid, and Debian-based distros
- [**openSUSE**](https://www.opensuse.org/) Tumbleweed
- [**Gentoo**](https://www.gentoo.org/) and Gentoo-based distros
- **macOS** 10.13 and newer
- **Windows** 8.1 and newer

## Tools and other stuff used
- curl
- bspatch
- [powdersn0w_pub](https://github.com/dora2-iOS/powdersn0w_pub) - dora2ios; [LukeZGD fork](https://github.com/LukeZGD/powdersn0w_pub)
- [ipwndfu](https://github.com/LukeZGD/ipwndfu) - axi0mX, Linus Henze, synackuk; LukeZGD fork
- [ipwnder_lite](https://github.com/dora2-iOS/ipwnder_lite/tree/7265a06d184e433989db640d5e83ea58d5862609) - dora2ios (used on macOS)
- [iPwnder32](https://github.com/dora2-iOS/iPwnder32/tree/243ea5c6d1bd15f8bdd0b3a1ff4a7729bc14bac4) - dora2ios (old version with libusb, used on Linux)
- [gaster](https://github.com/0x7ff/gaster/) - 0x7ff
- [daibutsuCFW](https://github.com/dora2-iOS/daibutsuCFW) - dora2ios; [LukeZGD fork](https://github.com/LukeZGD/daibutsuCFW)
- [libimobiledevice](https://github.com/libimobiledevice/libimobiledevice) - libimobiledevice
- [libirecovery](https://github.com/libimobiledevice/libirecovery) - libimobiledevice
- [libideviceactivation](https://github.com/libimobiledevice/libideviceactivation) - libimobiledevice
- [tsschecker](https://github.com/tihmstar/tsschecker) - tihmstar; [1Conan fork](https://github.com/1Conan/tsschecker) v413
- [futurerestore](https://github.com/tihmstar/futurerestore) - tihmstar;
    - [LukeZGD fork](https://github.com/LukeZGD/futurerestore) used on Linux for restoring 32-bit devices
    - [LukeeGD fork](https://github.com/LukeeGD/futurerestore) used on Linux/Windows for restoring A7/A8 devices
    - [futurerestore](https://github.com/futurerestore/futurerestore/) v259 used on macOS
- [iBoot32Patcher](https://github.com/dora2-iOS/iBoot32Patcher/) - dora2ios fork
- [idevicerestore](https://github.com/libimobiledevice/idevicerestore) - libimobiledevice; [LukeZGD fork](https://github.com/LukeZGD/idevicerestore)
- [idevicererestore](https://github.com/LukeZGD/daibutsuCFW/tree/main/src/idevicererestore) from daibutsuCFW (used on custom IPSW restores for A5/A6 devices)
- [kloader from Odysseus](https://www.youtube.com/watch?v=fh0tB6fp0Sc)
- [kloader from axi0mX](https://github.com/axi0mX/ios-kexec-utils/blob/master/kloader) (used on iOS 4/5 only)
- [kloader_hgsp from nyan_satan](https://twitter.com/nyan_satan/status/945203180522045440) (used on h3lix only)
- [partial-zip](https://github.com/matteyeux/partial-zip)
- [zenity](https://github.com/GNOME/zenity); [macOS/Windows builds](https://github.com/ncruces/zenity)
- 32-bit bundles from [OdysseusOTA](https://www.youtube.com/watch?v=Wo7mGdMcjxw), [OdysseusOTA2](https://www.youtube.com/watch?v=fh0tB6fp0Sc), [alitek12](https://www.mediafire.com/folder/b1z64roy512wd/FirmwareBundles), [gjest](https://www.reddit.com/r/jailbreak/comments/6yrzzj/release_firmware_bundles_for_ios_841_ipad21234567/) (modified bundles for daibutsuCFW)
- A7 patches from [MatthewPierson](https://github.com/MatthewPierson/iPhone-5s-OTA-Downgrade-Patches)
- iPad 2 iOS 4.3.x bundles from [selfisht, Ralph0045](https://www.reddit.com/r/LegacyJailbreak/comments/1172ulo/release_ios_4_ipad_2_odysseus_firmware_bundles/)
- [EtasonJB](https://www.theiphonewiki.com/wiki/EtasonJB)
- [Pangu](https://www.theiphonewiki.com/wiki/Pangu)
- [p0sixspwn](https://www.theiphonewiki.com/wiki/p0sixspwn)
- [unthredeh4il](https://www.theiphonewiki.com/wiki/Unthredera1n#unthredeh4il)
- SSH Ramdisk tar from [SSH-Ramdisk-Maker-and-Loader](https://github.com/Ralph0045/SSH-Ramdisk-Maker-and-Loader)
- Bootstrap tar from [SpiritNET](https://invoxiplaygames.uk/projects/spiritnet/)
