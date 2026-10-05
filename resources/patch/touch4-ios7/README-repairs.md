# iPod touch 4 iOS 7 repairs

The normal iPod4,1 7.1.2/11D257 custom-IPSW flow automatically applies the
Bluetooth, CS42L59 audio, system rotation and partial wallpaper repairs. There is no
additional option, launcher or filename suffix. The original DRA v6 bootloaders and N81
NOR DeviceTree are retained.

Resources, the downloadable AppleCS42L59Audio donor, source, symbol maps and
maintainer tests are in [Peterdobby/touch4-ios7-hardware](https://github.com/Peterdobby/touch4-ios7-hardware).
`repairs.sh` downloads a pinned, checksum-verified bundle and applies the binary
patches with the Kit's existing `bspatch`. This repair path has no Python build
or local-donor requirement. The ordinary saved kernelcache is also used by
Just Boot.

Cached custom IPSWs with an older/missing
`saved/touch4-ios7/touch4-version` record are rebuilt under their ordinary names. The record includes the resource bundle checksum
and complete IPSW checksum. A verified cached IPSW can restore its saved boot
kernel if that cache was removed.

Music playback and Bluetooth were reported working on an 8 GB N81 device.
Safari rotation in both directions, return to portrait, rotation lock and
lock/unlock were verified after a full OS reboot with the signed backboardd
and motion module used by this bundle. The module corrects only backboardd's
CoreMotion model cache before sensor initialization; it does not repair every
app's independent CoreMotion use. It adds no shared-cache or kernel changes.
**System sound effects remain unresolved. Wallpaper support is
partial: the default image displays, but Settings' wallpaper gallery remains
broken.** The refactored shell path reproduces the tested kernel, signed
BTServer, signed backboardd and motion module exactly. A fresh full restore
through the normal Kit flow was completed and the device owner reported no
problems. Broader boot/audio/Bluetooth coverage is still needed.

The repaired BTServer and backboardd need the existing Aquila signature
runtime, which is installed for this device even with the optional Cydia bootstrap disabled.
That configuration is not yet hardware-tested.
