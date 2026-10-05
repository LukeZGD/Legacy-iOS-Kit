# SPDX-License-Identifier: GPL-3.0-or-later
# iPod4,1 / 11D257 repairs. Builders and the CS59 donor are in the resource repository.

touch4_ios7_hash() {
    [[ -s $1 ]] && [[ $($sha1sum "$1" | awk '{print $1}') == "$2" ]]
}

touch4_ios7_resources() {
    [[ $device_type != "iPod4,1" ]] && return
    [[ $device_target_build != "11D257" ]] && error "Unsupported iPod4,1 iOS 7 build."
    local revision="c500dd6aabc604e0709555c0c8837454ff519cd0"
    local url="https://raw.githubusercontent.com/Peterdobby/touch4-ios7-hardware/$revision/artifacts/touch4-ios7-11D257-v3.tar.gz"
    local archive="../saved/touch4-ios7/11D257/repairs-v3.tar.gz"
    touch4_ios7_bundle_sha1="4045b86169a015927168960833f1aaf3eeb0181f"
    touch4_ios7_assets="../saved/touch4-ios7/11D257/repairs-v3"
    mkdir -p "$touch4_ios7_assets"
    if ! touch4_ios7_hash "$archive" "$touch4_ios7_bundle_sha1"; then
        file_download "$url" "$archive" "$touch4_ios7_bundle_sha1"
    fi
    touch4_ios7_hash "$archive" "$touch4_ios7_bundle_sha1" || error "Cannot verify iPod4,1 repair resources."
    tar -xzf "$archive" -C "$touch4_ios7_assets" || error "Cannot extract iPod4,1 repair resources."
    touch4_ios7_hash "$touch4_ios7_assets/kernel.patch" "667ffc12db0bc6e364cdfda631163ad781af7361" && \
    touch4_ios7_hash "$touch4_ios7_assets/BTServer.patch" "dc18fd4a3dfc7d5326a145f4ff4e66bce01ba669" && \
    touch4_ios7_hash "$touch4_ios7_assets/backboardd.patch" "84eb00fbe857071ea9fe26ac79bf1a7fb555fce3" && \
    touch4_ios7_hash "$touch4_ios7_assets/VirtualAudio.patch" "f0f018ee2e95144f5d23193f5d2a2e9800b934f6" && \
    touch4_ios7_hash "$touch4_ios7_assets/rootfs.tar" "b82ce76e735e05bf928985af6ee91ab7ca350009" || \
        error "Cannot verify extracted iPod4,1 repair resources."
}

touch4_ios7_kernel() {
    local source="$1"
    local target="$2"
    local work="touch4-ios7-kernel"
    mkdir -p "$work" "$(dirname "$target")"
    "$dir/xpwntool" "$source" "$work/original" || error "Cannot decode iPod4,1 kernelcache."
    if touch4_ios7_hash "$work/original" "fbfdd4e26ea6d8027957502faf16b13a551121fd"; then
        [[ $source != "$target" ]] && cp "$source" "$target"
        return 0
    fi
    touch4_ios7_hash "$work/original" "25b673fce8d7bc7551f526a0d648fb4a7acaf506" || \
        error "Unsupported 11D257 donor kernel."
    log "Applying iPod4,1 CS42L59 audio patch"
    $bspatch "$work/original" "$work/patched" "$touch4_ios7_assets/kernel.patch" || error "Cannot patch iPod4,1 kernel."
    touch4_ios7_hash "$work/patched" "fbfdd4e26ea6d8027957502faf16b13a551121fd" || error "Patched kernel verification failed."
    "$dir/xpwntool" "$work/patched" "$work/kernelcache" -t "$source" || error "Cannot pack iPod4,1 kernelcache."
    "$dir/xpwntool" "$work/kernelcache" "$work/check" || error "Cannot verify iPod4,1 kernelcache."
    touch4_ios7_hash "$work/check" "fbfdd4e26ea6d8027957502faf16b13a551121fd" || error "Kernelcache round trip failed."
    mv "$work/kernelcache" "$target" || error "Cannot save repaired kernelcache."
}

touch4_ios7_rootfs() {
    local work="touch4-ios7-rootfs"
    mkdir -p "$work"
    log "Applying iPod4,1 Bluetooth, rotation, audio capture and partial wallpaper repairs"
    "$dir/hfsplus" rootfs.dec extract usr/sbin/BTServer "$work/BTServer" || error "Cannot extract BTServer."
    touch4_ios7_hash "$work/BTServer" "2248a64e807e5c233c71843adbc0a43826d6bd46" || error "Unsupported 11D257 BTServer."
    $bspatch "$work/BTServer" "$work/BTServer.patched" "$touch4_ios7_assets/BTServer.patch" || error "Cannot patch BTServer."
    touch4_ios7_hash "$work/BTServer.patched" "9a3b693bf0368a128f624da105d17209cee63056" || error "Patched BTServer verification failed."
    "$dir/hfsplus" rootfs.dec extract usr/libexec/backboardd "$work/backboardd" || error "Cannot extract backboardd."
    touch4_ios7_hash "$work/backboardd" "86e4e86f587e2caa85bebaf9d5e6970b53a36a18" || error "Unsupported 11D257 backboardd."
    $bspatch "$work/backboardd" "$work/backboardd.patched" "$touch4_ios7_assets/backboardd.patch" || error "Cannot patch backboardd."
    touch4_ios7_hash "$work/backboardd.patched" "d4674d1f94a44692bd8c8e7bcb5010aad9593818" || error "Patched backboardd verification failed."
    local audio="Library/Audio/Plug-Ins/HAL/VirtualAudio.plugin/VirtualAudio"
    "$dir/hfsplus" rootfs.dec extract "$audio" "$work/VirtualAudio" || error "Cannot extract VirtualAudio."
    touch4_ios7_hash "$work/VirtualAudio" "c8881ddf01691aa90b642ff04b5d107608bc86b8" || error "Unsupported 11D257 VirtualAudio."
    $bspatch "$work/VirtualAudio" "$work/VirtualAudio.patched" "$touch4_ios7_assets/VirtualAudio.patch" || error "Cannot patch VirtualAudio."
    touch4_ios7_hash "$work/VirtualAudio.patched" "e0e8173ee4302b6f00f84277c2c147a8ee7aa0aa" || error "Patched VirtualAudio verification failed."
    "$dir/hfsplus" rootfs.dec rm usr/sbin/BTServer || error "Cannot replace BTServer."
    "$dir/hfsplus" rootfs.dec add "$work/BTServer.patched" usr/sbin/BTServer || error "Cannot add patched BTServer."
    "$dir/hfsplus" rootfs.dec chmod 755 usr/sbin/BTServer || error "Cannot set BTServer permissions."
    "$dir/hfsplus" rootfs.dec chown 0:0 usr/sbin/BTServer || error "Cannot set BTServer ownership."
    "$dir/hfsplus" rootfs.dec rm usr/libexec/backboardd || error "Cannot replace backboardd."
    "$dir/hfsplus" rootfs.dec add "$work/backboardd.patched" usr/libexec/backboardd || error "Cannot add patched backboardd."
    "$dir/hfsplus" rootfs.dec chmod 755 usr/libexec/backboardd || error "Cannot set backboardd permissions."
    "$dir/hfsplus" rootfs.dec chown 0:0 usr/libexec/backboardd || error "Cannot set backboardd ownership."
    "$dir/hfsplus" rootfs.dec rm "$audio" || error "Cannot replace VirtualAudio."
    "$dir/hfsplus" rootfs.dec add "$work/VirtualAudio.patched" "$audio" || error "Cannot add patched VirtualAudio."
    "$dir/hfsplus" rootfs.dec chmod 775 "$audio" || error "Cannot set VirtualAudio permissions."
    "$dir/hfsplus" rootfs.dec chown 0:80 "$audio" || error "Cannot set VirtualAudio ownership."
    "$dir/hfsplus" rootfs.dec untar "$touch4_ios7_assets/rootfs.tar" || error "Cannot apply Bluetooth/rotation/capture/wallpaper resources."
}

touch4_ios7_cached_ipsw() {
    local image="$1"
    local kernel="../saved/touch4-ios7/11D257/kernelcache"
    local stamp="../saved/touch4-ios7/touch4-version"
    [[ -s $stamp ]] || return 1
    [[ $(cat "$stamp") == "$touch4_ios7_bundle_sha1 $($sha1sum "$image" | awk '{print $1}')" ]] || return 1
    # Recover the exact boot cache from this validated IPSW, even if saved/ was cleared.
    unzip -p "$image" kernelcache.release.n81 > touch4-ios7-cached-kernel || return 1
    "$dir/xpwntool" touch4-ios7-cached-kernel touch4-ios7-cached-raw >/dev/null 2>&1 || return 1
    touch4_ios7_hash touch4-ios7-cached-raw "fbfdd4e26ea6d8027957502faf16b13a551121fd" || return 1
    cp touch4-ios7-cached-kernel "$kernel" || error "Cannot recover saved iPod4,1 kernelcache."
    echo "device_target_build=11D257" > "../saved/touch4-ios7/$device_ecid"
}

touch4_ios7_record_ipsw() {
    local image="$1"
    printf '%s %s\n' "$touch4_ios7_bundle_sha1" "$($sha1sum "$image" | awk '{print $1}')" > "../saved/touch4-ios7/touch4-version" || \
        error "Cannot record Custom IPSW repair version."
}
