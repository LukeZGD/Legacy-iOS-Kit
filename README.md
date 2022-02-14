# iOS-OTA-Downgrader

- **Downgrade/restore and jailbreak supported iOS devices to signed OTA firmwares**
- **Linux and macOS** are supported
- **Read the ["How to Use" wiki page](https://github.com/LukeZGD/iOS-OTA-Downgrader/wiki/How-to-Use) for a step-by-step tutorial**
- **Read the ["Troubleshooting" wiki page](https://github.com/LukeZGD/iOS-OTA-Downgrader/wiki/Troubleshooting) for tips, frequent questions, and troubleshooting**

## Other features
- iOS 6.1.3 and 8.4.1 downgrades have the option to **jailbreak** the install
    - For iOS 10.3.3, use [TotallyNotSpyware](https://totally-not.spyware.lol) or [sockH3lix](https://github.com/SongXiaoXi/sockH3lix) to jailbreak
- This script can also restore your device to other iOS versions that you have SHSH blobs for (32-bit devices only)
- This script can also be used to just enter kDFU mode (32-bit devices only)

## Supported devices
- [Identify your device here](https://ipsw.me/device-finder)
- **iPhone 5C and iPad mini 3 devices are NOT supported!**
    - iPhone 5C can still be restored to versions that you have SHSH blobs for

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

<details>
    <summary>For Pangu 32-bit users:</summary>
    <ul><li>For 32-bit users using Pangu and normal method, install the latest untether for your iOS version <a href="https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/tag/untether">here</a></li></ul>
</details>

## Supported OS versions/distros
- [**Ubuntu**](https://ubuntu.com/) 20.04 and newer, and Ubuntu-based distros like [Linux Mint](https://www.linuxmint.com/)
- [**Arch Linux**](https://www.archlinux.org/) and Arch-based distros like [EndeavourOS](https://endeavouros.com/)
- [**Fedora**](https://getfedora.org/) 33 and newer
- [**Debian**](https://www.debian.org/) 11 Bullseye, Testing and Unstable
- [**openSUSE**](https://www.opensuse.org/) Tumbleweed and Leap 15.3
- **macOS** 10.13 and newer

## Tools and other stuff used
- cURL
- bspatch
- [ipwndfu](https://github.com/LukeZGD/ipwndfu) - LukeZGD fork
- [iPwnder32](https://github.com/dora2-iOS/iPwnder32) - dora2ios
- [ipwnder_lite](https://github.com/dora2-iOS/ipwnder_lite) - dora2ios
- [daibutsuCFW](https://github.com/dora2-iOS/daibutsuCFW) - dora2ios
- [libimobiledevice](https://github.com/libimobiledevice/libimobiledevice) - libimobiledevice
- [libirecovery](https://github.com/libimobiledevice/libirecovery) - libimobiledevice
- [imobiledevice-net](https://github.com/libimobiledevice-win32/imobiledevice-net) - libimobiledevice-win32 (macOS build)
- ipsw tool from [xpwn](https://github.com/LukeZGD/xpwn) - LukeZGD fork
- Python 2 (for ipwndfu, rmsigchks, SimpleHTTPServer)
- [tsschecker](https://github.com/tihmstar/tsschecker) - tihmstar
- [futurerestore](https://github.com/m1stadev/futurerestore/tree/test) - m1stadev fork
- [kloader](https://www.youtube.com/watch?v=fh0tB6fp0Sc)
- [kloader5 for iOS 5](https://www.pmbonneau.com/cydia/com.pmbonneau.kloader5_1.2_iphoneos-arm.deb)
- [kloader_hgsp for iOS 10](https://twitter.com/nyan_satan/status/945203180522045440)
- [partial-zip](https://github.com/matteyeux/partial-zip)
- [zenity](https://github.com/GNOME/zenity)
- [zenity](https://github.com/ncruces/zenity) (macOS)
- 32-bit bundles are from [OdysseusOTA](https://www.youtube.com/watch?v=Wo7mGdMcjxw), [OdysseusOTA2](https://www.youtube.com/watch?v=fh0tB6fp0Sc), [alitek12](https://www.mediafire.com/folder/b1z64roy512wd/FirmwareBundles), [gjest](https://www.reddit.com/r/jailbreak/comments/6yrzzj/release_firmware_bundles_for_ios_841_ipad21234567/)
- [EtasonJB](https://www.theiphonewiki.com/wiki/EtasonJB)
- [p0sixspwn](https://www.theiphonewiki.com/wiki/p0sixspwn)
