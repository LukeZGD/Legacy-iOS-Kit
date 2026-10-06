# iPod touch 4 iOS 7 repairs

The normal iPod4,1 7.1.2/11D257 custom-IPSW flow automatically applies the
Bluetooth, CS42L59 audio playback/capture, system rotation, system sound effects and static wallpaper gallery repairs. There is no
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
The refactored shell path reproduces the tested kernel, signed
BTServer, signed backboardd and motion module exactly. A fresh full restore
through the normal Kit flow was completed and the device owner reported no
problems with the v2 bundle.

The v3/v4 bundles also repair Voice Memos and video recording by adding a signed
dependency to VirtualAudio. Its guarded module recognizes only iPod4,1/N81AP
and the exact supported plugin, then corrects its writable model cache from
the unknown-product profile to the existing K93 single-microphone routing
database and handlers. VirtualAudio's executable code and empty entitlements
are preserved. This capture fix adds no kernel, shared-cache, bootloader or
launch-configuration changes. Voice Memos and video recording/playback, plus
music playback, were confirmed working by the device owner after the guarded
repair was installed. A full reboot and fresh restore with the capture/UI repairs in v4, broader
microphone routes/DSP/gains, and broader boot/audio/Bluetooth coverage are
still untested.

The repaired BTServer, backboardd and VirtualAudio need the existing Aquila signature
runtime, which is installed for this device even with the optional Cydia bootstrap disabled.
That configuration is not yet hardware-tested.

V4 installs the newer N81 SystemSoundRingerSettings policy for charging,
lock/unlock and keyboard events, while preserving all other stock Default
policies. It also clears the cached procedural-wallpaper capability in the
existing Kit MobileGestalt template. Missing dynamic resources otherwise give
Settings zero-sized wallpaper category buttons. The static gallery and existing
iPod wallpaper links are retained; dynamic wallpapers are not supplied.
These are rootfs overlays, with no additional binary or boot-chain changes.
The owner confirmed system sound effects and accepted the wallpaper repair
after live installation. Native probes verified 90×135 category thumbnails
and 66 factory gallery items. Full reboot/fresh v4 restore and broader mute
or notification behavior have not yet been tested.
