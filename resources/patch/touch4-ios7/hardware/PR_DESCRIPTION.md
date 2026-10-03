Add iPod4,1 iOS 7 Bluetooth/audio repairs and partial wallpaper resource support

The iPod4,1 iOS 7.1.2 custom-IPSW flow lacks the N81 Bluetooth model/resources
and uses a CS42L61 codec instead of CS42L59. This change builds the repairs
inside the existing restore workflow, including a menu toggle and macOS
launcher. The device owner has tested the integrated version and reports
**Bluetooth and sound working normally**.

The build extracts Bluetooth firmware from the selected 6.1.6 IPSW, patches
and signs BTServer while retaining its entitlements, enables the generic
Bluetooth capability, and creates a hash-guarded CS42L59 kernel. A kernel-only
N81 IIS bridge preserves the existing DRA bootloaders and original NOR
DeviceTree. Experimental IPSW filenames, kernel caches and Just Boot selection
are isolated from the standard path.

**Wallpaper support is partial:** only the iOS 7 default wallpaper displays.
The Settings wallpaper directory/gallery still does not work normally. The
resource links in this patch must not be presented as a complete wallpaper fix.

Validation: five host integration tests, 51 Thumb bridge emulation cases at
three KASLR slides, exact kernel output and Img3 round trip, assembly reproduction,
and real HFS overlay installation/readback, including 67 wallpaper targets.
Earlier temporary v6 hardware tests confirmed clean wired stereo, speaker and
lock/unlock playback; the latest integrated test confirms normal Bluetooth
and sound, according to the device owner.

Remaining limitations: audio requires a locally supplied, hash-pinned internal
iOS 7 CS42L59 donor; no donor binary or download is included in this repository.
A full restore log, repeated DRA cold boots, Bluetooth sleep/wake, additional
audio rates/capture paths, and broader device coverage remain to be collected.
Rotation is not repaired. See `resources/patch/touch4-ios7/hardware/README.md`
for exact inputs, reproduction steps, addresses and hardware test status.
