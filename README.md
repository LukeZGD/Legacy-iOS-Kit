# Legacy iOS Kit

- (formerly iOS-OTA-Downgrader)
- **An all-in-one tool to downgrade/restore, save SHSH blobs, and jailbreak legacy iOS devices**
- Supported on **Linux and macOS**
- **Read the ["How to Use" wiki page](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/How-to-Use) for instructions**
- **Read the ["Troubleshooting" wiki page](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Troubleshooting) for tips, frequent questions, and troubleshooting**

## Features
- Legacy iOS Kit supports all 32-bit iOS devices, and some A7/A8 64-bit devices
- Restore to signed OTA versions (iOS 8.4.1 and/or 6.1.3) on A5/A6 devices
- Restore some 32-bit devices to other iOS versions without blobs
    - This includes downgrading iPhone 3GS, iPhone 4 GSM and CDMA, iPod touch 2, touch 3, iPad 1
- Restore with SHSH blobs on supported devices
- Restore to other iOS versions with iOS 7 blobs (powdersn0w)
- Jailbreak all 32-bit iOS devices on (almost) any iOS version
    - Available on iOS versions 3.1.3 to 9.3.4
    - Only unsupported versions are iOS 9.0.x and iPad 2 on 4.3.x
- Hacktivation for iPhone 2G, 3G, 3GS (activate without valid SIM card)
- Restore to iOS 10.3.3 (signed OTA version) on supported A7 devices
- Save onboard and Cydia SHSH blobs for 32-bit devices
- Enter pwned iBSS/kDFU mode for supported 32-bit devices
- Boot SSH Ramdisk for 32-bit devices
- Clear NVRAM for 32-bit devices
- Device activation using ideviceactivation (useful for iOS 4 and lower)
- The latest baseband will be flashed for A5/A6 devices with baseband
- Dumping and stitching baseband to IPSW (requires `--disable-bbupdate`)

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

- Restoring with SHSH blobs, jailbreaking, and using SSH Ramdisks are supported on the following devices:
    - Supports all 32-bit iOS devices
    - iPhone 2G, 3G, 3GS, 4, 4S, 5, 5C
    - iPad 1, 2, 3, 4, mini 1
    - iPod touch 1, 2, 3, 4, 5
- Restoring with SHSH blobs is also supported on most A7/A8 devices:
    - See [SEP/BB Compatibility Chart](https://docs.google.com/spreadsheets/d/1Mb1UNm6g3yvdQD67M413GYSaJ4uoNhLgpkc7YKi3LBs/edit#gid=1191207636) for iOS versions that can be restored to
    - iPhone 5S, 6, 6 Plus
    - iPad Air 1, mini 2, mini 3
    - iPod touch 6
- Restoring with powdersn0w is supported on the following devices:
    - iPhone 4 GSM - targets iOS 4.0 to 7.1.1
    - iPhone 4 CDMA - targets iOS 5.0 to 7.1.1 (4.2.x is not functional)
    - iPhone 4S, 5, 5C, iPad 2 Rev A, iPad 4, iPod touch 5 - targets iOS 5.0 to 9.3.5
    - iPad 1 - targets iOS 4.3 to 5.1 (4.2.1 and 3.2.x are not functional)
    - iPod touch 3 - targets iOS 4.0 to 5.1 (3.1.x is not functional)
    - Using powdersn0w requires iOS 7.1.x blobs for your device
        - For iPhone 5 and 5C, both 7.0.x and 7.1.x blobs can be used
        - For iPad 4, only 7.0.x blobs can be used
        - For iPad 1 and iPod touch 3, 5.1.1 blobs are used instead
- Restoring to other unsigned versions without blobs is supported on the following devices:
    - iPhone 3GS - targets iOS 3.1.3 to 5.1.1
    - iPod touch 2 - targets iOS 3.1.3 to 4.1

## Supported OS versions/distros

#### Supported architectures: x86_64, arm64, armhf

- [**Ubuntu**](https://ubuntu.com/) 22.04 and newer, and Ubuntu-based distros like [Linux Mint](https://www.linuxmint.com/)
- [**Arch Linux**](https://www.archlinux.org/) and Arch-based distros like [EndeavourOS](https://endeavouros.com/)
- [**Fedora**](https://getfedora.org/) 37 and newer
- [**Debian**](https://www.debian.org/) 12 Bookworm and newer, Sid, and Debian-based distros
- [**openSUSE**](https://www.opensuse.org/) Tumbleweed
- [**Gentoo**](https://www.gentoo.org/) and Gentoo-based distros
- **macOS** 10.13 and newer (10.15 and newer recommended)

## Tools and other stuff used
- curl
- bspatch
- [powdersn0w_pub](https://github.com/dora2-iOS/powdersn0w_pub) - dora2ios; [LukeZGD fork](https://github.com/LukeZGD/powdersn0w_pub)
    - [Most of the exploit ramdisks used are from kok3shidoll's repo](https://github.com/kok3shidoll/untitled)
    - [5C 7.0.x exploit ramdisk is from Ralph0045's iloader repo](https://github.com/Ralph0045/iloader)
    - [iPad 1 exploit ramdisk is from Ralph0045's iBoot-5-Stuff repo](https://github.com/Ralph0045/iBoot-5-Stuff)
- [ipwndfu](https://github.com/LukeZGD/ipwndfu) - axi0mX, Linus Henze, synackuk; LukeZGD fork
- [ipwnder_lite](https://github.com/dora2-iOS/ipwnder_lite/tree/7265a06d184e433989db640d5e83ea58d5862609) - dora2ios (used on macOS)
- [iPwnder32](https://github.com/dora2-iOS/iPwnder32/tree/243ea5c6d1bd15f8bdd0b3a1ff4a7729bc14bac4) - dora2ios (old version with libusb used on Linux)
- [gaster](https://github.com/0x7ff/gaster/) - 0x7ff
- [daibutsuCFW](https://github.com/dora2-iOS/daibutsuCFW) - dora2ios; [LukeZGD fork](https://github.com/LukeZGD/daibutsuCFW)
- [daibutsu](https://github.com/kok3shidoll/daibutsu) - dora/kok3shidoll, Clarity
- [libimobiledevice](https://github.com/libimobiledevice/libimobiledevice) - libimobiledevice
- [libirecovery](https://github.com/libimobiledevice/libirecovery) - libimobiledevice
- [libideviceactivation](https://github.com/libimobiledevice/libideviceactivation) - libimobiledevice
- [tsschecker](https://github.com/tihmstar/tsschecker) - tihmstar; [1Conan fork](https://github.com/1Conan/tsschecker) v413
- [futurerestore](https://github.com/tihmstar/futurerestore) - tihmstar;
    - [LukeZGD fork](https://github.com/LukeZGD/futurerestore) used on Linux for restoring 32-bit devices
    - [LukeeGD fork](https://github.com/LukeeGD/futurerestore) used on Linux for restoring A7/A8 devices
- [iBoot32Patcher](https://github.com/dora2-iOS/iBoot32Patcher/) - dora2ios fork
- [idevicerestore](https://github.com/libimobiledevice/idevicerestore) - libimobiledevice; [LukeZGD fork](https://github.com/LukeZGD/idevicerestore)
- [idevicererestore](https://github.com/LukeZGD/daibutsuCFW/tree/main/src/idevicererestore) from daibutsuCFW (used on custom IPSW restores for A5/A6 devices)
- [kloader from Odysseus](https://www.youtube.com/watch?v=fh0tB6fp0Sc)
- [kloader from axi0mX](https://github.com/axi0mX/ios-kexec-utils/blob/master/kloader) (used on iOS 4/5 only)
- [kloader for iOS 5](https://www.pmbonneau.com/cydia/com.pmbonneau.kloader5_1.2_iphoneos-arm.deb)
- [kloader_hgsp from nyan_satan](https://twitter.com/nyan_satan/status/945203180522045440) (used on h3lix only)
- [jq](https://github.com/jqlang/jq)
- [partialZipBrowser](https://github.com/tihmstar/partialZipBrowser)
- [zenity](https://github.com/GNOME/zenity); [macOS build](https://github.com/ncruces/zenity)
- 32-bit bundles from [OdysseusOTA](https://www.youtube.com/watch?v=Wo7mGdMcjxw), [OdysseusOTA2](https://www.youtube.com/watch?v=fh0tB6fp0Sc), [alitek12](https://www.mediafire.com/folder/b1z64roy512wd/FirmwareBundles), [gjest](https://www.reddit.com/r/jailbreak/comments/6yrzzj/release_firmware_bundles_for_ios_841_ipad21234567/) (modified bundles for daibutsuCFW)
- A7 patches from [MatthewPierson](https://github.com/MatthewPierson/iPhone-5s-OTA-Downgrade-Patches)
- iPad 2 iOS 4.3.x bundles from [selfisht, Ralph0045](https://www.reddit.com/r/LegacyJailbreak/comments/1172ulo/release_ios_4_ipad_2_odysseus_firmware_bundles/)
- [sshpass](https://sourceforge.net/project/sshpass)
- Bootstrap tar from [SpiritNET](https://invoxiplaygames.uk/projects/spiritnet/)
- [Cydia HTTPatch](https://cydia.invoxiplaygames.uk/package/cydiahttpatch) for 3.1.3 downgrades/jailbreaks
- [Pangu](https://www.theiphonewiki.com/wiki/Pangu)
- [p0sixspwn](https://www.theiphonewiki.com/wiki/p0sixspwn)
- [evasi0n](https://www.theiphonewiki.com/wiki/Evasi0n)
- [g1lbertJB](https://github.com/g1lbertJB/g1lbertJB)
- [UntetherHomeDepot](https://www.theiphonewiki.com/wiki/UntetherHomeDepot)
- [greenpois0n](https://github.com/OpenJailbreak/greenpois0n/tree/0f1eac8e748abb200fc36969e616aaad009f7ebf)
- Some patches from [PwnageTool](https://www.theiphonewiki.com/wiki/PwnageTool), [sn0wbreeze](https://www.theiphonewiki.com/wiki/sn0wbreeze), [redsn0w](https://www.theiphonewiki.com/wiki/redsn0w)
- SSH Ramdisk tars from [SSH-Ramdisk-Maker-and-Loader](https://github.com/Ralph0045/SSH-Ramdisk-Maker-and-Loader) and [msftguy's ssh-rd](https://github.com/msftguy/ssh-rd)
