# iOS-OTA-Downgrader

- **A multi-purpose script to downgrade/restore and jailbreak supported legacy iOS devices**
- **iPhone4Down: Downgrade iPhone 4 GSM on Linux/Windows (using powdersn0w)**
- **Linux, macOS, and Windows** are supported
    - Windows usage is not recommended
- **Read the ["How to Use" wiki page](https://github.com/LukeZGD/iOS-OTA-Downgrader/wiki/How-to-Use) for a step-by-step tutorial**
- **Read the ["Troubleshooting" wiki page](https://github.com/LukeZGD/iOS-OTA-Downgrader/wiki/Troubleshooting) for tips, frequent questions, and troubleshooting**

## Other features
- Option to **jailbreak** iOS 6.1.3 and 8.4.1 downgrades
    - For iOS 10.3.3 downgrades, use [TotallyNotSpyware](https://totally-not.spyware.lol)
- Restore to other iOS versions **with SHSH blobs**
    - Supports 32-bit/A7/A8 devices, iOS 5 to 12
    - Also supports iPad 2 iOS 4.3.x, iPhone 4 iOS 4.x
- The latest baseband will be used for 32-bit devices if applicable
- Place device to pwned iBSS/kDFU mode for 32-bit devices
- Clear NVRAM for iPhone 4 GSM (Disable/Enable Exploit)
- Restore iPhone 4 to iOS 7.1.2 with the option to jailbreak
- Restore supported devices to their latest iOS version
- Save on-board and Cydia SHSH blobs for 32-bit devices

## Supported devices
- [Identify your device here](https://ipsw.me/device-finder)
- **iPhone 5C and iPad mini 3 devices are NOT supported by OTA downgrades**
    - These devices still support restoring to other iOS versions with SHSH blobs
- **iPhone4Down (downgrading without blobs) supports iPhone 4 GSM only (iPhone3,1)**
    - All iPhone 4 models still support restoring with SHSH blobs and to iOS 7.1.2

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
        <tr><td>iPhone 5s</td></tr>
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
        <tr>
            <td>iOS 7.1.2</td>
            <td>iPhone 4 (all models)</td></tr>
        </tr>
        <tr>
            <td>iOS 4.3 to 6.1.3</td>
            <td>iPhone 4 GSM</td>
        </tr>
    </tbody>
</table>

<details>
    <summary>For 32-bit devices jailbroken with Pangu:</summary>
    <ul><li>For 32-bit devices using Pangu and jailbroken method, install the latest untether for your iOS version <a href="https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/tag/untether">here</a></li></ul>
</details>

## Supported OS versions/distros

#### Supported architectures: x86_64, arm64, armhf (Linux)

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
- [ipwndfu](https://github.com/LukeZGD/ipwndfu) - Linus Henze, synackuk; LukeZGD fork
- [ipwnder_lite](https://github.com/dora2-iOS/ipwnder_lite/tree/7265a06d184e433989db640d5e83ea58d5862609) - dora2ios (used on macOS)
- [iPwnder32](https://github.com/dora2-iOS/iPwnder32/tree/243ea5c6d1bd15f8bdd0b3a1ff4a7729bc14bac4) - dora2ios (old version with libusb, used on Linux)
- [gaster](https://github.com/0x7ff/gaster/) - 0x7ff
- [daibutsuCFW](https://github.com/dora2-iOS/daibutsuCFW) - dora2ios; [LukeZGD fork](https://github.com/LukeZGD/daibutsuCFW)
- [libimobiledevice](https://github.com/libimobiledevice/libimobiledevice), [libirecovery](https://github.com/libimobiledevice/libirecovery) - libimobiledevice
- [tsschecker](https://github.com/tihmstar/tsschecker) - tihmstar; [1Conan fork](https://github.com/1Conan/tsschecker)
- [futurerestore](https://github.com/tihmstar/futurerestore) - tihmstar;
    - [LukeZGD fork](https://github.com/LukeZGD/futurerestore) used on Linux for restoring 32-bit devices
    - [LukeeGD fork](https://github.com/LukeeGD/futurerestore) used on Linux/Windows for restoring A7/A8 devices
    - [futurerestore version](https://github.com/futurerestore/futurerestore/) used on macOS
- [idevicerestore](https://github.com/libimobiledevice/idevicerestore) - libimobiledevice; [LukeZGD fork](https://github.com/LukeZGD/idevicerestore)
- [idevicererestore](https://github.com/LukeZGD/daibutsuCFW/tree/main/src/idevicererestore) from daibutsuCFW (used on custom IPSW restores for A5/A6 devices)
- [kloader](https://www.youtube.com/watch?v=fh0tB6fp0Sc)
- [kloader5 for iOS 5](https://www.pmbonneau.com/cydia/com.pmbonneau.kloader5_1.2_iphoneos-arm.deb)
- [kloader_hgsp for iOS 10](https://twitter.com/nyan_satan/status/945203180522045440) (used on h3lix only)
- [partial-zip](https://github.com/matteyeux/partial-zip)
- [zenity](https://github.com/GNOME/zenity); [macOS/Windows builds](https://github.com/ncruces/zenity)
- 32-bit bundles from [OdysseusOTA](https://www.youtube.com/watch?v=Wo7mGdMcjxw), [OdysseusOTA2](https://www.youtube.com/watch?v=fh0tB6fp0Sc), [alitek12](https://www.mediafire.com/folder/b1z64roy512wd/FirmwareBundles), [gjest](https://www.reddit.com/r/jailbreak/comments/6yrzzj/release_firmware_bundles_for_ios_841_ipad21234567/) (modified bundles for daibutsuCFW)
- A7 patches from [MatthewPierson](https://github.com/MatthewPierson/iPhone-5s-OTA-Downgrade-Patches)
- iPad 2 iOS 4.3.x bundles from [selfisht, Ralph0045](https://www.reddit.com/r/LegacyJailbreak/comments/1172ulo/release_ios_4_ipad_2_odysseus_firmware_bundles/)
- [EtasonJB](https://www.theiphonewiki.com/wiki/EtasonJB)
- [Pangu](https://www.theiphonewiki.com/wiki/Pangu)
- [p0sixspwn](https://www.theiphonewiki.com/wiki/p0sixspwn)
- [unthredeh4il](https://www.theiphonewiki.com/wiki/Unthredera1n#unthredeh4il)
