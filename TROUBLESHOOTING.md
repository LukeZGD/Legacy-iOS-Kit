# TROUBLESHOOTING

## Common issues
- **If something in the process does not work for you:** try unplugging/replugging the device, switching between different USB ports/cables, also try USB 2.0 or 3.0 ports
- **IPSW file integrity** will be verified before restoring and/or creating custom IPSW (if custom IPSW is already created, this will be skipped) This is done to make sure that the IPSW is not corrupt or incomplete.
- **For users having issues with missing libraries/tools:** re-install dependencies by deleting the `libimobiledevice` folder in `resources`, then run the script again.
- If your device is not being detected in normal mode, make sure to also trust the computer by selecting "Trust" at the pop-up.
  - For Windows and macOS users, double-check if the device is being detected by iTunes/Finder.

## Windows
- Windows users may encounter errors like `Unable to send APTicket` or `Unable to send iBEC` in the restore process.
  - To fix this, [follow steps 1 to 5 here](https://github.com/m1stadev/futurerestore/tree/test#unable-to-send-ibec-error--8).
  - Run the script again and let the device exit recovery mode.
  - When the device boots up, jailbreak the device and run the script again. This time, it will get past the previous errors mentioned.
- If you want to restore your A7 device on Windows, you need to first put the device in pwnDFU mode with signature checks disabled. Since entering pwnDFU mode is not supported on Windows, you need to use a Mac/Linux machine or another iOS device to do so. If your device is not in pwnDFU mode, the restore will NOT proceed!
  - Windows users may create a Linux live USB. This can easily be done with tools like [Ventoy](https://www.ventoy.net/)
  - For entering pwnDFU mode, use ipwndfu, iPwnder32, or iPwnder Lite ([Tutorial](https://www.reddit.com/r/LegacyJailbreak/comments/pyzyc2/tutorial_short_tutorial_to_downgrade_most_a7_to/))

## macOS
- macOS users may have to install libimobiledevice and libirecovery from [Homebrew](https://brew.sh/) or [MacPorts](https://www.macports.org/). This is optional, but recommended.
  - For Homebrew: `brew install libimobiledevice libirecovery`
  - For MacPorts: `sudo port install libimobiledevice libirecovery`
  - The script will detect this automatically and will use the Homebrew/MacPorts versions of the tools

## Linux
- ipwndfu is unfortunately very unreliable on Linux, you may have to try multiple times.
  - You may also try in a live USB.

## A7 devices
- Do not use USB-C to lightning cables as this can prevent a successful restore
- If the script cannot find your device in pwnREC mode or gets stuck, you may have to start over by [force restarting](https://support.apple.com/guide/iphone/iph8903c3ee6/ios) and re-entering recovery/DFU mode
- Use an Intel or Apple Silicon PC/Mac as entering pwnDFU (checkm8) may be a lot more unreliable on AMD devices
- Apple Silicon Mac users running macOS 11.3 and newer may encounter issues entering pwnDFU mode (see [issue #114](https://github.com/LukeZGD/iOS-OTA-Downgrader/issues/114))
- For more troubleshooting steps for entering pwnDFU mode, see [issue #126](https://github.com/LukeZGD/iOS-OTA-Downgrader/issues/126)
- Other than the above, unfortunately there is not much else I can do to help regarding entering pwnDFU mode.

## 32-bit devices
- To make sure that SSH is successful, try these steps: Reinstall OpenSSH/Dropbear, reboot and rejailbreak, then reinstall them again
- To devices with baseband, this script will restore your device with the latest baseband (except when jailbreak is enabled, and on iPhone5,1 where there were reported issues)
- This script can also be used to just enter kDFU mode for all supported devices
- This script can work on virtual machines, but I will not provide support for them
- If you want to use other manually saved blobs for 6.1.3/8.4.1, create a folder named `saved`, then within it create another folder named `shsh`. You can then put your blob inside that folder.
  - The naming of the blob should be: `(ECID in Decimal)_(ProductType)_(Version)-(BuildVer).shsh(2)`
  - Example with path: `saved/shsh/123456789012_iPad2,1_8.4.1-12H321.shsh`

## Jailbreak Option for 32-bit devices
- If you have problems with Cydia, remove the ultrasn0w repo and close Cydia using the app switcher, then try opening Cydia again
- If you cannot find Cydia in your home screen, try accessing Cydia through Safari with `cydia://` and install "Jailbreak App Icons Fix" package from my Cydia repo
- p0sixspwn will be used for iOS 6.1.3, and EtasonJB or daibutsu for iOS 8.4.1
- For some devices, EtasonJB untether is unstable and not working properly, so daibutsu jailbreak will be used. See [PR #129](https://github.com/LukeZGD/iOS-OTA-Downgrader/pull/129) for more details
- For devices jailbroken with EtasonJB, there is no need to install "Stashing for #etasonJB" package, as stashing is already enabled
- For devices jailbroken with daibutsu, add the system repo for future updates to the untether: https://dora2ios.github.io/repo/
- For devices jailbroken with daibutsu and want to use Coolbooter Untetherer, [apply this fix/workaround](https://github.com/LukeZGD/iOS-OTA-Downgrader/issues/131#issuecomment-920022171) using Terminal (the commands need to be run as root)

## DFU Advanced Menu for 32-bit devices
- To enter DFU advanced menu, put your iOS device in recovery (A6 only), normal DFU (also A6 only), kDFU, or pwnDFU mode before running the script
- There are two options that can be used in the DFU advanced menu
- Select the "kDFU mode" option if your device is already in kDFU mode beforehand. Example of this is using kDFUApp by tihmstar; kDFUApp can also be installed from my repo: https://lukezgd.github.io/repo/
- For A6/A6X devices, "DFU mode (A6)" option can be used. This will use ipwndfu (or iPwnder32 for Mac) to put your device in pwnDFU mode, send pwned iBSS, and proceed with the downgrade/restore
- For A5/A5X devices, "pwnDFU mode (A5)" option can be used, BUT ONLY IF the device is put in pwnDFU mode beforehand, with [checkm8-a5](https://github.com/synackuk/checkm8-a5) using an Arduino and USB Host Shield
