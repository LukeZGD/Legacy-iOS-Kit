# iPod touch 4 iOS 7 hardware repair integration

This is an **opt-in experimental build integration**, based on Legacy iOS Kit
`33dcbfcf4d8791268292e1009e2955e3f02b4785`. It generates Bluetooth, audio and
wallpaper patches during the existing custom-IPSW build. No generated Apple
executables, firmware, kernelcaches, device identifiers or private logs are
included in this source change.

## Status

| Component | Physical-device result | Integrated restore status |
| --- | --- | --- |
| Bluetooth | User reports Bluetooth works normally in the tool-integrated test | Build and HFS readback verified; separate cold-boot/sleep-wake coverage not reported |
| Audio, v6 proof of concept | Clean wired left/right channels, speaker and playback after lock/unlock | Verified through temporary boot and manual RAM driver activation |
| Audio, kernel-only integration | User reports sound works normally in the tool-integrated test | Exact build reproduced and 51 emulation cases passed; repeated DRA cold boots and additional audio paths not separately confirmed |
| Wallpaper | User confirms only the iOS 7 default wallpaper displays | Directory overlay verified; Settings wallpaper gallery/directory **still does not work normally** |
| Rotation | Still broken | Outside this change |

The single test device is an 8 GB iPod4,1/N81AP running 7.1.2/11D257,
originally installed with the 6.1.6/10B500 DRA v6 iBoot chain. Earlier successful v6
audio tests used temporary 6.1.6 iBSS/iBEC loading. The user subsequently tested
the tool-integrated version and reported normal Bluetooth and sound. No full
restore log or separate repeated untethered cold-boot report was collected.

## Inputs and usage

On macOS, double-click `restore-touch4-ios7.command`. This opens the ordinary
Kit menu with jailbreak and the repair option enabled, using the local donor
cache at `saved/touch4-ios7/donors/AppleCS42L59Audio.kext`. The launcher disables
update checks to keep this test branch in use. In Restore/Downgrade → 7.1.2,
`Toggle Hardware Repairs` enables/disables the feature; the menu displays its
current state. This is a full custom-IPSW restore flow, with no temporary boot
or manual post-restore activation steps.

The launcher/cache do not supply a generally distributable donor. The local
cache must be populated separately with the hash-pinned files below. From an
ordinary terminal, `./restore.sh --touch4-hardware-fixes` uses the same cache.


Use the usual iPod4,1 iOS 7.1.2 custom-IPSW workflow with jailbreak enabled:

```sh
./restore.sh --jailbreak --touch4-hardware-fixes="/absolute/path/AppleCS42L59Audio.kext"
```

Select iPod4,1, target 7.1.2/11D257 and base 6.1.6/10B500 as usual. The option
is accepted only by that build path. Existing standard IPSWs are separated
from experimental outputs by a `-HardwareV1` filename suffix. Reusing a
HardwareV1 IPSW requires its matching generated kernel cache. Move an old
HardwareV1 IPSW aside when changing this patch version and rebuild it.

The additional kext input must contain these exact files:

| File | SHA-256 |
| --- | --- |
| `AppleCS42L59Audio` | `1970eb6c0754bd313e1b957e60d4149c9f48a60ede7363adc84419bea281cf88` |
| `Info.plist` | `cd15cf00a8d3face0857dbb2b2ba394f276bf3720e9b29c17afe18eb008cf7c0` |

The donor was extracted from a locally available internal iOS 7 image named
`11A63840h.dmg` (DTSDK build `11A384`, `iphoneos7.0.internal`). It is **not**
the public iPod 6.1.6 driver. Standard public iPhone3,3 7.1.2 and iPod4,1
6.1.6 IPSWs alone cannot reproduce this audio transplant. No donor download
is provided. This dependency must be resolved before treating the repair as
a generally available/default upstream feature.

Python 3.8+ is sufficient for building. The existing Kit `xpwntool`, `dmg`
and `hfsplus` are reused. BTServer is signed with `ldid` using its existing
entitlements; the helper obtains the same Procursus ldid release already
used elsewhere in the Kit. Unicorn is needed only for optional emulation.

## Build integration

1. Decode the target kernelcache, verify its exact raw-kernel hash and relink
   the native CS42L59 codec with the supplied symbol map.
2. Add the N81 IIS configuration bridge and interrupt-name correction to the
   kernel. Repack and decode again, requiring identical bytes.
3. Store the generated kernel under
   `saved/touch4-ios7/11D257/hardware/kernelcache`, then put it at the normal
   target KernelCache path inside the custom IPSW. The standard kernel cache
   remains in its original location.
4. Extract BlueTool from the selected 6.1.6 base RootFS. Extract its embedded
   BCM4329B1 LOCO HCD, validate 101 record boundaries and its hash, and generate
   the N81 boot/init/deepsleep scripts.
5. Patch the target BTServer, preserve and verify its entitlements, set the
   generic Kit MobileGestalt cache's Bluetooth capability, and untar these
   files plus the wallpaper links into the target RootFS before `dmg build`.
6. Record `touch4_hardware_profile=cs59-v1` alongside the device's saved build
   selection. Just Boot selects that kernel and the original Kit DeviceTree;
   it fails before USB access if the selected kernel is missing.

The existing restore ramdisk, iBoot patches, DRA exploit and NOR DeviceTree
are reused without changes. A kernel-only bridge was chosen because replacing
the NOR tree with the v6 audio tree has not been validated against the initial
iOS 6 exploit stages.

## Technical details

### Bluetooth

N81's product hash is missing from the 11D257 BTServer classifier. It falls
into an unknown class whose Device ID vendor source is zero; registration
returns 101. At file offset `0x15b63c`, this patch replaces the iPad1,1
classifier product hash with N81's hash, using the same BCM4329B1 classification
whose vendor source is 2. This is scoped to BTServer; it does not spoof the
system model. At `0x163654`, the selected class's `isSupported` virtual pointer
changes from `0x76f1d` to the existing constant-true function `0x94f81`.
Other chipset operations and BLE flags are unchanged. Class identity and
cold-boot behavior still need broader testing.

### Audio

The public N92 kernel contains CS42L61; N81 needs CS42L59. The linker resolves
675 relocation fixups at `0x80dac000`, fixes the inherited Mikey vtable slot
introduced in 7.1, and adjusts the compiled superclass virtual call from
`0x3f0` to `0x3f4`. It preserves the prelink XML's types and ID/IDREF graph,
including 14 OSData tags, and emits XNU-compatible `<tag/>` empty tags.

The original N81 `audio0/reg` is a 32-byte legacy structure, while the current
AppleARMIISDevice expects 36 bytes. The bridge at `0x80dac400`, called from
`0x804fbc1c`, translates **only** the exact eight-word N81 structure. Other
short inputs remain rejected, and inputs of at least 36 bytes retain the
original path. The converted configuration uses flags `0x10`, 6 MHz input
MCLK and IIS slave role. `AppleEmbeddedAudio` looks up the original tree's
`codec` interrupt name instead of `mikey`. The bridge uses PC-relative branches
and constants and introduces no new absolute pointers for KASLR to fix up.

V5's flags `0x11` produced playback-dependent hiss, strongest on the right,
with normal song speed and pitch. Restarting mediaserverd did not help.
Changing only the master/slave bit to `0x10` in v6 eliminated the reported
hiss on both wired channels and the speaker. That is an isolated hardware
result; it does not validate every rate, capture path, or startup sequence.

### Wallpaper

Create `/Library/Wallpaper/iPod` links with `~ipod` names pointing at existing
`iPhone` PNGs and thumbnails. There are 67 links and no additional image data.
The user confirms that only the default iOS 7 wallpaper displays; the stock
Settings gallery/directory still does not work normally. This is a partial
resource repair, not a complete gallery fix.

## Verification

```sh
python3 resources/patch/touch4-ios7/hardware/test_integration.py
bash -n restore.sh
# Optional, after generating the candidate; requires Unicorn 2.1.4:
python3 resources/patch/touch4-ios7/hardware/test_bridge.py \
  saved/touch4-ios7/11D257/hardware/kernel.n81.macho
```

Offline validation reproduced the original v6 linked kernel and the v7
kernel-only output exactly. The latter raw kernel is
`c082f2b423e04aa60a71840c573557d9564d70542f45468de6c60fc2159ff0a8`;
with the tested Kit template its Img3 is
`b473817cb826a8aad426dfc3b1d9b45335921f6c699b054dee04b794aba8e434`.
Assembly source compilation reproduces all 132 bridge bytes. All six
regular overlay files match HFS readback; every wallpaper link target exists.
BTServer permissions and MobileGestalt ownership were checked. Five host
integration tests cover input rejection, opt-in filenames, supported-device
scope and original/experimental Just Boot selection, plus enabling the repair in the normal restore menu, with no USB operations.

## Before requesting a non-draft merge

- Collect the full restore/startup log and verify repeated cold boots through
  the installed DRA v6 chain.
- Verify Bluetooth search/reconnect specifically from a cold boot, without
  manual BlueTool reinitialization, and after sleep/wake.
- Repair and test the Settings wallpaper gallery, preview and selection.
- Establish a reproducible donor source suitable for upstream users.
- Test additional devices/capacities and audio rates, recording and alerts.

Bluetooth and audio are now user-confirmed working in the integrated test.
Retain the explicit opt-in while the donor dependency and broader boot coverage
remain unresolved. Describe wallpaper as partial when submitting for review;
do not advertise a functioning Settings wallpaper gallery. The source follows the repository's GPL-3.0-or-later
license; generated Apple firmware and executables are not part of the patch.

## Latest hardware report — 2026-10-03

The device owner reported: Bluetooth normal; sound normal; wallpaper only shows
the iOS 7 default image, with the wallpaper directory/gallery still abnormal.
This report supersedes the earlier untested Bluetooth/audio integration status.
It does not establish repeated cold-boot, microphone, recording or additional
sample-rate coverage. No claim of a complete wallpaper repair is made.
