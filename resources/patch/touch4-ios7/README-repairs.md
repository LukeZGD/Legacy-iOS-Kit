# iPod touch 4 iOS 7 repairs

The normal iPod4,1 7.1.2/11D257 custom-IPSW flow automatically applies the
Bluetooth, CS42L59 audio and partial wallpaper repairs. There is no additional
option, launcher or filename suffix. The original DRA v6 bootloaders and N81
NOR DeviceTree are retained.

Resources, the downloadable AppleCS42L59Audio donor, source, symbol maps and
maintainer tests are in [Peterdobby/touch4-ios7-hardware](https://github.com/Peterdobby/touch4-ios7-hardware).
`repairs.sh` downloads a pinned, checksum-verified bundle and applies the binary
patches with the Kit's existing `bspatch`. This repair path has no Python build
or local-donor requirement. The ordinary saved kernelcache is also used by
Just Boot.

Cached custom IPSWs with an older/missing `.touch4-version` record are rebuilt
under their ordinary names. The record includes the resource bundle checksum
and complete IPSW checksum. A verified cached IPSW can restore its saved boot
kernel if that cache was removed.

Music playback and Bluetooth were reported working on an 8 GB N81 device.
**System sound effects and rotation remain unresolved. Wallpaper support is
partial: the default image displays, but Settings' wallpaper gallery remains
broken.** The refactored shell path reproduces the tested kernel and signed
BTServer exactly; a fresh device restore and broader boot/audio/Bluetooth
coverage are still needed.

The repaired BTServer needs the existing Aquila signature runtime, which is
installed for this device even with the optional Cydia bootstrap disabled.
That configuration is not yet hardware-tested.
