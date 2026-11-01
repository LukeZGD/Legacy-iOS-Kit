# iOS 10.3.4 untethered restore

This integration adds a jailbreak option to **Restore/Downgrade → Latest iOS (10.3.4) → Start Restore** for 32-bit iPhone 5, iPhone 5C and iPad 4 devices. It installs Socket 1.3's bootstrap, Zebra and Procyon during the restore. No sideloading, second DFU boot or installer app is needed.

## Using the option

1. Back up your device. **Start Restore erases all device data.**
2. Select the stock, unmodified iOS 10.3.4 (14G61) IPSW for the device family.
3. Choose Start Restore, read the warnings, and enable the jailbreak option. Declining uses the existing normal restore path.
4. Choose whether to reuse a compatible prepared IPSW or create a fresh one. Fresh creation offers the RAM option. Follow this restore flow's DFU instructions.
5. Allow the device to boot and complete Setup normally. Zebra should appear on the Home Screen. **The first boot can take longer than subsequent boots.**

Only the signed Latest iOS 10.3.4 route is enabled. The saved-SHSH, tethered and powdersn0w/DRA routes are not implemented by this integration. Enabling the jailbreak on an unsupported route stops before device preparation. A saved custom IPSW can be reused, but Apple signing requests are still made for the current restore.

**Do not enter pwnDFU separately through Useful Utilities for this flow.** That route did not work in testing. If pwnDFU fails after IPSW creation, relaunch, return through the same Restore/Downgrade menu, select Reuse IPSW, and follow that flow's DFU instructions.

## Hardware results and limits

| Device | Board | Result with the original tested integration |
| --- | --- | --- |
| iPhone5,1 | n41ap | Firmware checked; hardware untested |
| iPhone5,2 | n42ap | Restore, untethered reboot, Zebra and tweak injection passed |
| iPhone5,3 | n48ap | Firmware checked; hardware untested |
| iPhone5,4 | n49ap | Restore, untethered reboot, Zebra and tweak injection passed |
| iPad3,4 | p101ap | Restore, untethered reboot, Zebra and tweak injection passed |
| iPad3,5 | p102ap | Firmware checked; hardware untested |
| iPad3,6 | p103ap | Firmware checked; hardware untested |

Manual hardware tests used macOS and Legacy iOS Kit base `23622f8fe72c09952089d5145a7b008cfcc90d9b`. They are not hardware tests of the newer upstream host binaries used by this PR. Linux is expected to work but has not been tested. All host binaries remain in upstream's existing platform/architecture directories; this integration does not replace them.

Regular CoolBooter installed and booted secondary iOS 6 on iPhone5,2 and iPad3,4. Primary iOS 10 continued to boot with Zebra and tweaks. This does not establish compatibility with every secondary firmware or untested model.

## Untether warnings

- Procyon documents about **93% boot success on iPad 4 with iOS 10.3.2 or later**. A failed boot attempt may require a manual reboot. This concerns boot attempts, not a percentage of devices. [Procyon information](https://github.com/staturnzz/procyon#information)
- Socket leaves the untether disabled by default on affected iPads. Enabling this restore option installs it. The Socket guide states that the same issue does not affect iPhone 5 or iPhone 5C. [Socket guidance](https://ios.cfw.guide/installing-socket/)
- This uses Procyon, as Socket does. Comparable reliability is expected on the same model and firmware; this integration has not independently measured identical rates. Keep backups on every supported model.
- **Do not install CoolBooter Untetherer.** Procyon reports that it causes a blank screen. The regular CoolBooter application is separate. [Procyon information](https://github.com/staturnzz/procyon#information)
- **Do not sideload or run the Socket app on this installation.** Coexistence is not supported and may cause conflicts. For Socket's optional non-jailbroken state, use a fresh stock restore and Socket normally.

## Implementation and review

`allinone_stage.py` separates system files from a deferred data-volume installation plan. `prepare.py` modifies the restore ramdisk and system image while preserving the installed stock iBoot, kernel, dyld cache and launchd. A separate patched kernel is used only during restoration. The tested system-volume growth is 160 MiB; no extra partition is created.

The restore ramdisk's `nvram` wrapper invokes the finalizer on Apple's late `bootdelay=0` operation, after data-volume preparation and before final unmount. The finalizer verifies the mounted target, populates the data files, generates Procyon stages from the target kernelcache and dyld cache, and verifies the persistent installation. See [ALLINONE.txt](ALLINONE.txt) for the cache relocation and package metadata details.

The implementation under this directory is carried over unchanged from the tested standalone integration. Earlier app/jumpstart source, assets and regression tests are retained for provenance; the exposed restore option uses only the all-in-one path. There is no second-stage or first-boot observation menu. Upstream review may choose a different layout or menu integration.

The proposal does not include the standalone fork's updater, offline policy, branding or startup transcript option. Restore logs, image records, optional DCSD traces and identity checks are part of the iOS 10 implementation itself. Logs are saved under `saved/ios10`; review device identifiers and local paths before sharing them. No log is uploaded automatically and no DCSD cable is required.

Host regression tests use mocked device/USB operations, synthetic image fixtures and native parser tests. They do not establish boot success on hardware:

```sh
bash -n restore.sh
bash -n resources/ios10/restore.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_ios10*.py'
```

Source and license notices are preserved in [NOTICE.txt](NOTICE.txt). Credit to LukeZGD and Legacy iOS Kit contributors, staturnz for Socket and Procyon, Zebra's developers, and the authors of the existing restore and jailbreak components. This integration does not introduce a new exploit.
