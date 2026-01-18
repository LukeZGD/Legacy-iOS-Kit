# Legacy iOS Kit

- (formerly iOS-OTA-Downgrader)
- **An all-in-one tool to [restore/downgrade](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Restore-Downgrade), [save SHSH blobs](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Saving-SHSH-blobs), [jailbreak](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Jailbreaking) legacy iOS devices, and more**
- Supported on **Linux and macOS**
- **Read the ["How to Use" wiki page](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/How-to-Use) for instructions**
- **Read the ["Troubleshooting" wiki page](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Troubleshooting) for tips, frequent questions, and troubleshooting**

## Features
- Legacy iOS Kit supports all 32-bit iOS devices, and some 64-bit (A7/A8/A9/A10/A11) devices
    - Devices that received iOS 16 and newer will only have limited functionality (e.g. sideloading) and some features like SSH ramdisk are not supported
    - Legacy iOS Kit defines *legacy devices* as all iOS devices that are vulnerable to a bootrom exploit (checkm8 and older)
- Restore to signed OTA versions (iOS 8.4.1 and/or 6.1.3) on A5/A6 devices
- Restore to iOS 10.3.3 (signed OTA version) on supported A7 devices
- Restore supported devices to unsigned versions with SHSH blobs
- Restore to unsigned iOS versions with iOS 7 blobs (powdersn0w)
- Restore supported 32-bit devices to unsigned iOS versions "without" blobs
    - Includes downgrading iPhone 2G, 3G, 3GS, iPhone 4 GSM and CDMA, iPod touch 1, 2, 3, iPad 1
    - "without" is in quotes because powdersn0w uses iOS 5/7 blobs for touch 3 and A4 devices, but it is signed for everyone to use
    - Other devices however are true blobless
- Tethered downgrades/restores to supported iOS versions for A5(X)/A6(X) and some other 32-bit devices
- Jailbreak all 32-bit iOS devices on nearly any iOS version
    - Available on iOS versions 3.0 to 9.3.4 with some small exceptions
- Hacktivation for iPhone 2G, 3G, 3GS, 4 GSM (activate without valid SIM card)
- Boot SSH Ramdisk for supported 32-bit and 64-bit devices
- Save Onboard SHSH blobs for supported 32-bit and 64-bit devices
- Sideload IPA files for supported devices on Linux (and macOS)
- Save SHSH blobs from Cydia servers for 32-bit devices
- Enter pwned iBSS/kDFU mode for supported 32-bit devices
- Save onboard SHSH blobs for jailbroken 64-bit devices (deverser)
    - This also saves onboard Cryptex APTicket and seed for iOS 16+ (x8A4)
- Install [TrollStore](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/TrollStore) using SSH Ramdisk for supported 64-bit devices on iOS 14/15
- Clear NVRAM for 32-bit devices
- Device activation using ideviceactivation (especially useful for iOS 4 and lower)
- The latest baseband will be flashed for certain A5/A6 devices (for iPhone 4S, 5, 5C, iPad 4, mini 1)
    - For more info on baseband, go to [Baseband Update](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Baseband-Update) wiki page
- Dumping and stitching baseband to IPSW (requires `--disable-bbupdate`)
- Dumping and stitching activation records to IPSW (requires `--activation-records`)
- [App Management](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/App-Management) - Install IPA (AppSync), dump apps as IPA, list installed apps
- [Data Management](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Data-Management) - Backup and restore, mount device, erase all content and settings
- [Misc Utilities](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Misc-Utilities) - Pair device, export data and battery info, shutdown/restart device, and more

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

- Restoring with SHSH blobs, jailbreaking, and using SSH ramdisks are supported on the following devices:
    - iPhone 2G, 3G, iPod touch 1
    - iPhone 3GS, 4, 4S, 5, 5C
    - iPad 1, 2, 3, 4, mini 1
    - iPod touch 2, 3, 4, 5
- Restoring with SHSH blobs and using SSH Ramdisks are also supported on some 64-bit devices:
    - iPhone 5S, 6, 6S, SE 2016, 7 (including Plus variants)
    - iPad Air 1, 2
    - iPad mini 2, 3, 4
    - iPod touch 6, 7
    - Versions that can be restored to depend on SEP/BB compatibility
    - Although SEP/BB compatibility does not matter anymore for A9(X)/A10(X) devices thanks to [turdus merula](https://sep.lol)
- Restoring with iOS 14.3-15.x and 16.6+ SHSH blobs using futurerestore is also supported on these devices (SSH ramdisks not supported):
    - iPhone 8, X
    - iPad 5
    - iPad Pro 9.7/12.9 1st gen
- Restoring with **powdersn0w** is supported on the following devices and target version range:
    - iPhone 4 GSM - iOS 4.0 to 7.1.1
    - iPhone 4 CDMA - iOS 4.2.6 to 7.1.1
    - iPhone 4S, 5, 5C, iPad 2 Rev A, iPod touch 5 - iOS 5.0 to 9.3.5
    - iPad 1 - iOS 3.2 to 5.1
    - iPod touch 3 - iOS 3.1.1 to 5.1
    - Using powdersn0w requires iOS 7.1.x blobs for your device
        - No blob requirement for iPhone 4, iPad 1, iPod touch 3 (7.1.2 and 5.1.1 are signed)
        - For iPhone 5 and 5C, both 7.0.x and 7.1.x blobs can be used
- Restoring **tethered** to any version is supported on the following devices:
    - iPhone 4 (3,2 and 3,3), 4S, 5, 5C
    - iPad 2, 3, 4, mini 1
    - iPod touch 3, 4, 5
- Restoring to other unsigned versions without blobs is supported on the following devices and target version range:
    - iPhone 2G, 3G, 3GS, iPod touch 1, touch 2 - All versions are supported
    - Lowest downgradable version is 2.0. Going to 1.x does not work
    - For jailbreaking support, see below
- [Restoring the iPod touch 3rd gen to iOS 6 untethered](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/touch3-ios6)
- [Restoring the iPod touch 4th gen to iOS 7 tethered](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/touch4-ios7)
- Jailbreaking for 32-bit devices and versions support:
    - iPhone 2G and touch 1 - 3.1.3 only
    - iPhone 3G and touch 2 - 4.2.1, 4.1, and 3.1.3
    - iPhone 3GS - All versions are supported (all release versions from 3.0 to 6.1.6)
    - Other devices - All versions from 3.1.3 to 9.3.4 are supported, with some exceptions
    - For more details, go to the ["Jailbreaking" wiki page](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Jailbreaking)


## Supported OS versions/distros

#### Supported architectures: x86_64, arm64

- **macOS** 10.11 and newer
    - macOS 14.6 and newer recommended for Apple Silicon Macs
- [**Ubuntu**](https://ubuntu.com/) 22.04 and newer, and Ubuntu-based distros like [Linux Mint](https://www.linuxmint.com/)
- [**Fedora**](https://getfedora.org/) 40 and newer, Fedora Atomic (Silverblue, Kinoite, etc.) also supported
- [**Debian**](https://www.debian.org/) 12 Bookworm and newer, Sid, and Debian-based distros
- [**Arch Linux**](https://www.archlinux.org/) and Arch-based distros like [EndeavourOS](https://endeavouros.com/) and [CachyOS](https://cachyos.org)
- Less tested distros: [**openSUSE Tumbleweed**](https://get.opensuse.org/tumbleweed/), [**Gentoo**](https://www.gentoo.org/), [**Void Linux**](https://voidlinux.org/)

## Tools and other stuff used
- curl
- bspatch
- [powdersn0w_pub](https://github.com/dora2-iOS/powdersn0w_pub) - dora2ios; [LukeZGD fork](https://github.com/LukeZGD/powdersn0w_pub)
    - [Most of the exploit ramdisks used are from kok3shidoll's repo](https://github.com/kok3shidoll/untitled)
    - [iPhone 5C 7.0.x exploit ramdisk is from m1zole](https://github.com/m1zole/untitled_pub)
    - [Other iPhone 5/5C ramdisks are from Ralph0045's iloader repo](https://github.com/Ralph0045/iloader)
    - [iPad 1 exploit ramdisk is from Ralph0045](https://github.com/Ralph0045/iBoot-5-Stuff)
- [ipwndfu](https://github.com/LukeZGD/ipwndfu) - axi0mX; LukeZGD fork
- [iPwnder32](https://github.com/LukeZGD/iPwnder32) libusb - dora2ios; LukeZGD fork
- [gaster](https://github.com/LukeZGD/gaster) - 0x7ff; LukeZGD fork
- [primepwn](https://github.com/LukeZGD/primepwn)
- [a6meowing](https://github.com/kok3shidoll/a6meowing) - dora/kok3shidoll
- [reipwnder](https://github.com/kok3shidoll/reipwnder) - dora/kok3shidoll
- [daibutsuCFW](https://github.com/LukeZGD/daibutsuCFW) - dora2ios; LukeZGD fork
- [daibutsu](https://github.com/kok3shidoll/daibutsu) - dora/kok3shidoll, Clarity
- [libimobiledevice](https://github.com/LukeeGD/libimobiledevice) - libimobiledevice
- [libirecovery](https://github.com/LukeeGD/libirecovery) - libimobiledevice
- [libideviceactivation](https://github.com/LukeeGD/libideviceactivation) - libimobiledevice
- [ideviceinstaller](https://github.com/LukeeGD/ideviceinstaller) - libimobiledevice
- [ifuse](https://github.com/LukeeGD/ifuse) - libimobiledevice
- [static-cross-openssh](https://github.com/binary-manu/static-cross-openssh) - scp and ssh binaries (used on Linux only)
- [Motrix](https://github.com/agalwood/Motrix) - aria2c binaries
- [usbmuxd2](https://github.com/LukeZGD/usbmuxd2) - tihmstar; LukeZGD fork (used on Linux only, optional)
- [anisette-server](https://github.com/Dadoum/Provision) from Provision - Dadoum (used for sideloading on Linux)
- [AltServer-Linux](https://github.com/NyaMisty/AltServer-Linux) - NyaMisty (used for sideloading on Linux)
- [Sideloader](https://github.com/Dadoum/Sideloader) - Dadoum (used for sideloading on Linux and macOS)
- [tsschecker](https://github.com/1Conan/tsschecker) - tihmstar; 1Conan fork (v413)
- [darkhttpd](https://github.com/emikulic/darkhttpd)
- [x8A4](https://github.com/Cryptiiiic/x8A4) - Cryptiiiic (for getting Cryptex seed)
- [futurerestore](https://github.com/tihmstar/futurerestore) - tihmstar
    - [LukeZGD fork](https://github.com/LukeZGD/futurerestore) used for restoring 32-bit devices (not used in macos arm64)
    - [LukeeGD fork](https://github.com/LukeeGD/futurerestore) used for restoring A7 devices (mostly not used though)
    - [futurerestore nightly](https://github.com/futurerestore/futurerestore/) used for restoring A8/A9/A10/A11 devices
- [iBoot32Patcher](https://github.com/Merculous/iBoot32Patcher/) - Merculous fork
- [idevicerestore](https://github.com/LukeZGD/idevicerestore) - libimobiledevice; LukeZGD fork
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
- [datautils0](https://github.com/comex/datautils0) - comex (used for iPad 2 4.3.x kernel diffs)
- [sshpass](https://sourceforge.net/project/sshpass)
- Bootstrap tar from [SpiritNET](https://invoxiplaygames.uk/projects/spiritnet/)
- [Cydia HTTPatch](https://cydia.invoxiplaygames.uk/package/cydiahttpatch) for 3.1.3 downgrades/jailbreaks
- [EverPwnage](https://github.com/LukeZGD/EverPwnage)
- [Lyncis](https://github.com/staturnzz/lyncis)
- [Pangu](https://www.theapplewiki.com/wiki/Pangu)
- [p0sixspwn](https://www.theapplewiki.com/wiki/p0sixspwn)
- [evasi0n7](https://www.theapplewiki.com/wiki/Evasi0n7)
- [evasi0n](https://www.theapplewiki.com/wiki/Evasi0n)
- [g1lbertJB](https://github.com/g1lbertJB/g1lbertJB)
- [UntetherHomeDepot](https://www.theapplewiki.com/wiki/UntetherHomeDepot)
- [greenpois0n](https://github.com/OpenJailbreak/greenpois0n/tree/0f1eac8e748abb200fc36969e616aaad009f7ebf)
- Some patches from [PwnageTool](https://www.theapplewiki.com/wiki/PwnageTool), [sn0wbreeze](https://www.theapplewiki.com/wiki/sn0wbreeze), [redsn0w](https://www.theapplewiki.com/wiki/redsn0w)
- Many patches for the 3GS are made using patchers by Merculous (including [Bundle-Creation](https://github.com/Merculous/Bundle-Creation))
- SSH Ramdisk tars from Ralph0045's [SSH-Ramdisk-Maker-and-Loader](https://github.com/Ralph0045/SSH-Ramdisk-Maker-and-Loader) and msftguy's [ssh-rd](https://github.com/msftguy/ssh-rd)
- 64-bit SSH Ramdisk stuff is based on Nathan's [SSHRD_Script](https://github.com/verygenericname/SSHRD_Script) (iOS 12+), and exploit3dguy's iram tar from [iarchive.app](https://web.archive.org/web/20240324134204/https://ios7.iarchive.app/downgrade/making-ramdisk.html) (iOS 8)
    - [img4lib](https://github.com/xerub/img4lib) - xerub
    - [img4tool](https://github.com/tihmstar/img4tool) - tihmstar
- Tools used for dumping IPA - forks by rcky844
    - [ipainstaller](https://github.com/rcky844/ipainstaller)
    - [Clutch](https://github.com/rcky844/Clutch)
- For iPhone X restore patches:
    - Method by Mineek and Nathan
    - Mineek's [restored_external patcher](https://gist.github.com/mineek/16c2607c928477dcd273e680e40a1c90) for iPhone X downgrades to 14.3-15.x
    - [KPlooshFinder](https://github.com/plooshi/KPlooshFinder/tree/amfi-only)
    - [kerneldiff](https://gist.github.com/LukeZGD/8c719b613ca28d6883552437bdd500de)
