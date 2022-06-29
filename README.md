# iOS-OTA-Downgrader

- **Downgrade/restore and jailbreak supported iOS devices to signed OTA firmwares**
- **iPhone4Down: Downgrade your iPhone 4 on Linux (using ch3rryflower)**
- **Linux and macOS** are supported
    - **Partial support for Windows** - usage is not recommended
    - iPhone4Down is focused on Linux only - macOS is untested, Windows is unsupported
- **Read the ["How to Use" wiki page](https://github.com/LukeZGD/iOS-OTA-Downgrader/wiki/How-to-Use) for a step-by-step tutorial**
- **Read the ["Troubleshooting" wiki page](https://github.com/LukeZGD/iOS-OTA-Downgrader/wiki/Troubleshooting) for tips, frequent questions, and troubleshooting**

## Other features
- iOS 6.1.3 and 8.4.1 downgrades have the option to **jailbreak** the install
    - For iOS 10.3.3, use [TotallyNotSpyware](https://totally-not.spyware.lol) or [sockH3lix](https://github.com/SongXiaoXi/sockH3lix) to jailbreak
- This script can also restore your device to other iOS versions that you have SHSH blobs for (32-bit devices only, iOS 5 and newer only)
- This script can also be used to just enter kDFU mode (32-bit devices only)
- This script can also be used to restore your iPhone 4 back to iOS 7.1.2 with the option to jailbreak the install

## Supported devices
- [Identify your device here](https://ipsw.me/device-finder)
- **iPhone 5C and iPad mini 3 devices are NOT supported!**
    - iPhone 5C can still be restored to versions that you have SHSH blobs for
    - iPhone 4 devices also support restoring with SHSH blobs
- **iPhone4Down supports the iPhone 4 GSM (iPhone3,1) only**
    - You are on your own if you attempt to restore to versions not within the supported range (except for iOS 7.1.2)

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
        <tr>
            <td>iOS 7.1.2</td>
            <td rowspan=2>iPhone 4 GSM (iPhone3,1)</td>
        </tr>
        <tr><td>iOS 5.0 to 6.1.3</td></tr></tr>
    </tbody>
</table>

<details>
    <summary>For Pangu 32-bit users:</summary>
    <ul><li>For 32-bit users using Pangu and normal method, install the latest untether for your iOS version <a href="https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/tag/untether">here</a></li></ul>
</details>

## Supported OS versions/distros
- [**Ubuntu**](https://ubuntu.com/) 20.04 and newer, and Ubuntu-based distros like [Linux Mint](https://www.linuxmint.com/)
- [**Arch Linux**](https://www.archlinux.org/) and Arch-based distros like [EndeavourOS](https://endeavouros.com/)
- [**Fedora**](https://getfedora.org/) 35 and newer
- [**Debian**](https://www.debian.org/) 11 Bullseye and newer, Sid, and Debian-based distros
- [**openSUSE**](https://www.opensuse.org/) Tumbleweed, Leap 15.4
- **macOS** 10.13 and newer
- **Windows** 7 and newer

## Tools and other stuff used
- cURL
- bspatch
- python2 (ipwndfu, rmsigchks, SimpleHTTPServer), python3 (http.server)
- [ch3rryflower](https://web.archive.org/web/20200708040313/https://github.com/dora2-iOS/ch3rryflower) - dora2ios
- [ipwndfu](https://github.com/LukeZGD/ipwndfu) - LukeZGD fork
- [iPwnder32](https://github.com/dora2-iOS/iPwnder32) - dora2ios
- [ipwnder_lite](https://github.com/dora2-iOS/ipwnder_lite) - dora2ios
- [daibutsuCFW](https://github.com/dora2-iOS/daibutsuCFW) - dora2ios ([LukeZGD fork](https://github.com/LukeZGD/daibutsuCFW))
- [libimobiledevice](https://github.com/libimobiledevice/libimobiledevice), [libirecovery](https://github.com/libimobiledevice/libirecovery) - libimobiledevice ([macOS/Windows builds](https://github.com/libimobiledevice-win32/imobiledevice-net))
- [tsschecker](https://github.com/tihmstar/tsschecker) - tihmstar ([1Conan fork](https://github.com/1Conan/tsschecker))
- [futurerestore](https://github.com/futurerestore/futurerestore) - futurerestore beta (194 used for Windows only)
- [idevicerestore](https://github.com/LukeeGD/idevicerestore) - LukeZGD fork
- [kloader](https://www.youtube.com/watch?v=fh0tB6fp0Sc)
- [kloader5 for iOS 5](https://www.pmbonneau.com/cydia/com.pmbonneau.kloader5_1.2_iphoneos-arm.deb)
- [kloader_hgsp for iOS 10](https://twitter.com/nyan_satan/status/945203180522045440)
- [partial-zip](https://github.com/matteyeux/partial-zip)
- [zenity](https://github.com/GNOME/zenity) ([macOS/Windows builds](https://github.com/ncruces/zenity))
- 32-bit bundles from [OdysseusOTA](https://www.youtube.com/watch?v=Wo7mGdMcjxw), [OdysseusOTA2](https://www.youtube.com/watch?v=fh0tB6fp0Sc), [alitek12](https://www.mediafire.com/folder/b1z64roy512wd/FirmwareBundles), [gjest](https://www.reddit.com/r/jailbreak/comments/6yrzzj/release_firmware_bundles_for_ios_841_ipad21234567/) (modified bundles for daibutsuCFW)
- A7 patches from [MatthewPierson](https://github.com/MatthewPierson/iPhone-5s-OTA-Downgrade-Patches) (patches used for Windows only)
- [EtasonJB](https://www.theiphonewiki.com/wiki/EtasonJB)
- [evasi0n](https://www.theiphonewiki.com/wiki/Evasi0n)
- [evasi0n7](https://www.theiphonewiki.com/wiki/Evasi0n7)
- [Pangu](https://www.theiphonewiki.com/wiki/Pangu)
- [p0sixspwn](https://www.theiphonewiki.com/wiki/p0sixspwn)
- [unthredeh4il](https://www.theiphonewiki.com/wiki/Unthredera1n#unthredeh4il)
