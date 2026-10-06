loc="../saved/ipad6-ipados18"
patches="../resources/patch/ipad6-ipados18"

# when set to 1, it will recreate the binary patches for iBSS, iBEC, DeviceTree, and LLB
# this will need binaries of iBoot64Patcher, bsdiff, devicetree-parse, devicetree-repack, iBootpatch2
# to be placed in saved/ipad6-ipados18/bin
# the patches will be saved on saved/ipad6-ipados18
# recreating the patches must be done on macos, set below variable to 1 and i used this command
# /restore.sh --no-finder --no-device --device=iPad7,5 --sshrd
# repeat for iPad7,6 since devicetree patches are separate
ipad6_ipados18_recreate_patches=

# only "part 1" is automated (up to the end of "Wrapping up files" section in asdfugil guide)
# booting into ios 17, fixing up var, and tether boot are not implemented (yet)
ipad6_ipados18_ramdisk() {
    local loc="../saved/ipad6-ipados18"
    # 17.7 up until Trustcache for sshrd.
    # On LLB and DeviceTree, it will switch over to latest (17.7.11 as of this writing) for usage below
    local comps=("iBSS" "iBEC" "DeviceTree" "Kernelcache" "RestoreRamdisk" "Trustcache" "LLB" "DeviceTree")
    local name
    local iv
    local key
    local path
    local url
    local decrypt
    local opt
    local build_id="21H16"

    # start ramdisk stuff
    local ramdisk_path="$loc/ramdisk_$build_id"
    device_target_build="$build_id"
    device_fw_key_check
    ipsw_get_url $build_id
    mkdir -p $ramdisk_path
    rm -f $ramdisk_path/*.img4 $ramdisk_path/iBEC.im4p $ramdisk_path/iBSS.im4p

    for getcomp in "${comps[@]}"; do
        if [[ $getcomp == "LLB" ]]; then
            device_target_build="$device_latest_build"
            device_fw_key_check
            ipsw_get_url $device_target_build
        fi
        name=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .filename')
        iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .iv')
        key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .key')
        case $getcomp in
            "iBSS" | "iBEC" ) path="Firmware/dfu/";;
            "DeviceTree" | "LLB" ) path="Firmware/all_flash/";;
            "Trustcache" ) path="Firmware/";;
            * ) path="";;
        esac
        if [[ -z $name ]]; then
            local hwmodel
            ipsw_hwmodel_set
            hwmodel="$ipsw_hwmodel"
            case $getcomp in
                "iBSS" | "iBEC" | "LLB" ) name="$getcomp.$hwmodel.RELEASE.im4p";;
                "DeviceTree"     ) name="$getcomp.${device_model}ap.im4p";;
                "Kernelcache"    ) name="kernelcache.release.$hwmodel";;
                "Trustcache"     ) name="044-18147-018.dmg.trustcache";;
                "RestoreRamdisk" ) name="044-18147-018.dmg";;
            esac
        fi

        log "$getcomp"
        if [[ $getcomp == "RestoreRamdisk" && -e $ramdisk_path/ramdisk1.dmg ]]; then
            cp $ramdisk_path/ramdisk1.dmg $name
        elif [[ $getcomp == "RestoreRamdisk" ]]; then
            file_download https://github.com/LukeZGD/Legacy-iOS-Kit-Keys/releases/download/a/ipad6-ramdisk1.dmg ramdisk1.dmg 32f93cac47fb91dbc54e85131f950f742dfc947e
            cp ramdisk1.dmg $ramdisk_path/
            mv ramdisk1.dmg $name
        elif [[ -e $ramdisk_path/$name ]]; then
            cp $ramdisk_path/$name .
        else
            download_with_pzb "$ipsw_url" "${path}$name" "$name"
            cp $name $ramdisk_path/
        fi
        mv $name $getcomp.orig
        local reco="-i $getcomp.orig -o $getcomp.img4 -M ../resources/sshrd/IM4M$device_proc -T "
        case $getcomp in
            "iBSS" | "iBEC" )
                reco+="$(echo $getcomp | tr '[:upper:]' '[:lower:]') -A"
                "$dir/img4" -i $getcomp.orig -o $getcomp.dec -k ${iv}${key}
                mv $getcomp.orig $getcomp.orig0
                if [[ $ipad6_ipados18_recreate_patches == 1 && $getcomp == "iBSS" ]]; then
                    $loc/bin/iBoot64Patcher $getcomp.dec $getcomp.orig
                    $loc/bin/bsdiff $getcomp.dec $getcomp.orig $loc/$getcomp.patch
                elif [[ $ipad6_ipados18_recreate_patches == 1 ]]; then
                    $loc/bin/iBoot64Patcher $getcomp.dec $getcomp.orig -b 'rd=md0 debug=0x2014e -v wdt=-1' -n
                    $loc/bin/bsdiff $getcomp.dec $getcomp.orig $loc/$getcomp.patch
                else
                    $bspatch $getcomp.dec $getcomp.orig $patches/$getcomp.patch
                fi
            ;;
            "Kernelcache" )
                reco+="rkrn -J -P "
                if [[ $ipad6_ipados18_recreate_patches == 1 ]]; then
                    reco+="kc.bpatch"
                    "$dir/img4" -i $getcomp.orig -o kcache.raw
                    "$dir/KPlooshFinder" kcache.raw kcache.patched
                    "$dir/kerneldiff" kcache.raw kcache.patched kc.bpatch
                else
                    reco+="$patches/kc.bpatch"
                fi
            ;;
            "DeviceTree" )
                reco+="rdtr"
                "$dir/img4" -i $getcomp.orig -o DeviceTree
                if [[ $device_target_build == "$device_latest_build" && $ipad6_ipados18_recreate_patches == 1 ]]; then
                    $loc/bin/devicetree-parse DeviceTree > DeviceTree_${device_model}ap.jsonc
                    git apply $patches/dt-${device_model}ap.diff
                    $loc/bin/devicetree-repack DeviceTree_${device_model}ap.jsonc devicetred
                    $loc/bin/bsdiff DeviceTree devicetred $loc/dt-${device_model}ap.patch
                elif [[ $device_target_build == "$device_latest_build" ]]; then
                    $bspatch DeviceTree devicetred $patches/dt-${device_model}ap.patch
                fi
            ;;
            "Trustcache" ) reco+="rtsc";;
            "RestoreRamdisk" ) reco+="rdsk -A";;
            "LLB" )
                "$dir/img4" -i $getcomp.orig -k ${iv}${key} -o LLB.bin
                cp LLB.bin $loc/
                if [[ $ipad6_ipados18_recreate_patches == 1 ]]; then
                    $loc/bin/iBoot64Patcher LLB.bin LLB2.bin
                    $loc/bin/iBootpatch2 LLB2.bin LLB3.bin
                    $loc/bin/bsdiff LLB.bin LLB3.bin $loc/$getcomp.patch
                else
                    $bspatch LLB.bin LLB3.bin $patches/$getcomp.patch
                fi
            ;;
        esac
        [[ $device_target_build != "$device_latest_build" ]] && "$dir/img4" $reco
    done

    mv iBSS.img4 iBSS.im4p
    mv iBEC.img4 iBEC.im4p
    iBSS="iBSS"
    iBEC="iBEC"

    if [[ $device_argmode == "none" ]]; then
        mkdir -p $ramdisk_path/saved
        cp *.img4 iBEC.im4p iBSS.im4p $ramdisk_path/saved/
        log "Done creating SSH ramdisk files: $ramdisk_path/saved"
        pause
        return
    fi

    restore_prepare_pwnrec64

    log "Booting, please wait..."
    $irecovery -f RestoreRamdisk.img4
    $irecovery -c ramdisk
    $irecovery -f DeviceTree.img4
    $irecovery -c devicetree
    $irecovery -f Trustcache.img4
    $irecovery -c firmware
    $irecovery -f Kernelcache.img4
    $irecovery -c bootx
    sleep 6

    device_iproxy no-logging
    print "* Booted SSH ramdisk is based on: https://github.com/verygenericname/SSHRD_Script"
    device_sshpass alpine

    local found
    log "Waiting for device..."
    print "* You may need to unplug and replug your device."
    while [[ $found != 1 ]]; do
        found=$($ssh -p $ssh_port root@127.0.0.1 "echo 1")
        sleep 2
    done

    if [[ $mode == "device_enter_ramdisk" ]]; then
        menu_ramdisk
    fi
}

device_ipad6_ipados18_step1() {
    if [[ $device_argmode != "none" ]]; then
        device_enter_mode pwnDFU
    fi

    # blacktop/ipsw download
    local ipswtool_version="3.1.730"
    local ipswtool_filename="linux_${platform_arch}"
    [[ $platform == "macos" ]] && ipswtool_filename="macOS_universal"
    local ipswtool_download="https://github.com/blacktop/ipsw/releases/download/v${ipswtool_version}/ipsw_${ipswtool_version}_${ipswtool_filename}.tar.gz"
    if [[ ! -s $loc/ipsw ]]; then
        file_download "$ipswtool_download" "$(basename "$ipswtool_download")"
        tar -xvf "$(basename "$ipswtool_download")" ipsw
        mv ipsw $loc/ipsw
    fi
    $loc/ipsw >/dev/null
    if [[ $? != 0 ]]; then
        error "ipsw tool failed to open. Likely incompatible macOS version or other issue like download"
    fi

    mkdir -p out
    log "Processing dmg files from target IPSW"
    mkdir -p out
    local root="094-32804-038.dmg"
    local os="094-33089-038.dmg"
    local app="094-32014-038.dmg"
    for i in $root $os; do
        local key="MQZQVhUK6WZl4/vPH27CJ4coXeYR7h9tLWG056FVtqc="
        [[ $i == "$os" ]] && key="epccQmu0bRK1nGmd0HU3iGltnCe9XqydHAEMe1hlNO4="
        file_extract_from_archive "$ipsw_path.ipsw" $i.aea
        $loc/ipsw fw aea --key-val "base64:$key" $i.aea --output out
        [[ ! -s out/$i ]] && error "Decryption of $i.aea failed"
        rm $i.aea
    done
    mv out/$root root.dmg
    mv out/$os os.dmg
    file_extract_from_archive "$ipsw_path.ipsw" $app
    mv $app app.dmg

    ipad6_ipados18_ramdisk

    log "Dump onboard blobs on the iPad"
    $ssh -p $ssh_port root@127.0.0.1 "
        /sbin/mount_tmpfs /mnt5
        dd if=/dev/disk2 of=/mnt5/disk2.bin
    "
    $scp -P $ssh_port root@127.0.0.1:/mnt5/disk2.bin disk2.bin

    log "Create IM4M from onboard blob dump"
    "$dir/img4" -i disk2.bin -m IM4M
    cp IM4M $loc/

    log "Wrap LLB in img4"
    "$dir/img4" -i LLB3.bin -A -T ibss -M IM4M -o $loc/LLB.img4

    log "Mount preboot"
    $ssh -p $ssh_port root@127.0.0.1 "/sbin/mount_apfs $preboot_volume /mnt6"

    local boot_manifest_hash="$($ssh -p $ssh_port root@127.0.0.1 "cat /mnt6/active")"
    log "Got boot_manifest_hash: $boot_manifest_hash"

    log "Copying cryptex current to currend"
    $ssh -p $ssh_port root@127.0.0.1 "
        mkdir -p /mnt6/cryptex1/currend
        cp -a /mnt6/cryptex1/current/apticket.*.im4m /mnt6/cryptex1/currend
        cp -a /mnt6/cryptex1/current/*.{root_hash,trustcache} /mnt6/cryptex1/currend
    "

    local root_volume="/dev/disk1s8"
    local preboot_volume="/dev/disk1s5"
    if [[ $device_type == "iPad7,6" ]]; then
        root_volume="/dev/disk1s9"
        preboot_volume="/dev/disk1s6"
    fi
    if [[ ! $($ssh -p $ssh_port root@127.0.0.1 "ls $root_volume 2>/dev/null") ]]; then
        log "Create iOS 18 filesystem"
        $ssh -p $ssh_port root@127.0.0.1 "/sbin/newfs_apfs -A -D -o role=r -v Xystem /dev/disk0s1"
    fi

    log "Mounting new volume: $root_volume"
    $ssh -p $ssh_port root@127.0.0.1 "/sbin/mount_apfs $root_volume /mnt8"

    log "Transferring root.dmg to device, this will take a while."
    $scp -P $ssh_port root.dmg root@127.0.0.1:/mnt8/root.dmg

    log "Unmounting filesystems"
    $ssh -p $ssh_port root@127.0.0.1 "/sbin/umount /mnt8; /sbin/umount /mnt6"

    log "APFS invert"
    $ssh -p $ssh_port root@127.0.0.1 "/System/Library/Filesystems/apfs.fs/apfs_invert -d /dev/disk0s1 -s ${root_volume: -1} -n root.dmg"

    log "Mounting filesystems"
    $ssh -p $ssh_port root@127.0.0.1 "/sbin/mount_apfs $preboot_volume /mnt6; /sbin/mount_apfs $root_volume /mnt8"

    log "Transferring os.dmg to device, this will take a while."
    $scp -P $ssh_port os.dmg root@127.0.0.1:/mnt6/cryptex1/currend/os.dmg

    log "Transferring app.dmg to device, this will take a while."
    $scp -P $ssh_port app.dmg root@127.0.0.1:/mnt6/cryptex1/currend/app.dmg

    log "Mounting iOS 17"
    $ssh -p $ssh_port root@127.0.0.1 "/sbin/mount_apfs -o ro /dev/disk1s1 /mnt1"

    log "Add iPad 6 specific files"
    $ssh -p $ssh_port root@127.0.0.1 "
        find /mnt1 -iregex '.*j7[1-2]b.*' -type f -exec /bin/sh -c 'dirname=\"\$(echo \"{}\" | sed -E '\''s|^/mnt1(/.+)/.+$|\1|'\'')\"; filename=\"\$(echo \"{}\" | sed -E '\''s|/mnt1/.+/(.+)$|\1|'\'')\"; mkdir -p \"/mnt8/\${dirname}\"; cp -an \"{}\" \"/mnt8/\${dirname}/\${filename}\";' \;

        ln -s J171.Default.plist /mnt8/System/Library/EventTimingProfiles/J71b.Default.plist
        ln -s J171.Touch.plist /mnt8/System/Library/EventTimingProfiles/J71b.Touch.plist
        ln -s J171.Pencil.plist /mnt8/System/Library/EventTimingProfiles/J71b.Pencil.plist

        ln -s J172.Default.plist /mnt8/System/Library/EventTimingProfiles/J72b.Default.plist
        ln -s J172.Touch.plist /mnt8/System/Library/EventTimingProfiles/J72b.Touch.plist
        ln -s J172.Pencil.plist /mnt8/System/Library/EventTimingProfiles/J72b.Pencil.plist
    "

    log "Downgrade components"
    $ssh -p $ssh_port root@127.0.0.1 "
        mv /mnt8/Library/Wallpaper{,.bak}
        cp -a /mnt1/Library/Wallpaper /mnt8/Library

        mv /mnt8/Library/Audio/Plug-Ins{,.bak}
        cp -a /mnt1/Library/Audio/Plug-Ins /mnt8/Library/Audio

        mv /mnt8/usr/sbin/BlueTool{,.bak}
        cp -a /mnt1/usr/sbin/BlueTool /mnt8/usr/sbin
    "

    log "Patch RootFS and wrap up"
    $ssh -p $ssh_port root@127.0.0.1 "
        sed -i -e 's|cryptex1/current|cryptex1/currend|' /mnt8/usr/lib/dyld
        ldid -Icom.apple.dyld -S /mnt8/usr/lib/dyld
    "

    log "Wrap kernel in img4"
    file_extract_from_archive "$ipsw_path.ipsw" kernelcache.release.ipad7c
    "$dir/img4" -i kernelcache.release.ipad7c -M IM4M -o kernelcachd
    log "Transferring kernelcachd to device"
    $scp -P $ssh_port kernelcachd root@127.0.0.1:/mnt6/$boot_manifest_hash/System/Library/Caches/com.apple.kernelcaches/kernelcachd

    log "Wrap patched devicetree"
    "$dir/img4" -i devicetred -M IM4M -A -T dtre -o devicetred.img4
    log "Transferring devicetred.img4 to device"
    $scp -P $ssh_port devicetred.img4 root@127.0.0.1:/mnt6/$boot_manifest_hash/usr/standalone/firmware/devicetred.img4

    log "AVE firmware"
    file_extract_from_archive "$ipsw_path.ipsw" Firmware/ave/AppleAVE2FW_H9.im4p
    "$dir/img4" -i AppleAVE2FW_H9.im4p -M IM4M -o EVA.img4
    log "Transferring EVA.img4 to device"
    $scp -P $ssh_port EVA.img4 root@127.0.0.1:/mnt6/$boot_manifest_hash/usr/standalone/firmware/FUD/EVA.img4

    log "Extract $device_type_special SEP firmware"
    file_extract_from_archive "$ipsw_path.ipsw" Firmware/all_flash/sep-firmware.${device_model_special}.RELEASE.im4p
    mv sep-firmware.${device_model_special}.RELEASE.im4p $loc/sep-firmware.im4p

    log "Rebooting device"
    $ssh -p $ssh_port root@127.0.0.1 "/sbin/reboot"

    log "Done. Proceed to Step 2"
}

menu_ipad6_ipados18() {
    local menu_items
    local selected
    local back

    while [[ -z "$mode" && -z "$back" ]]; do
        menu_items=("Step 1: Setup iPadOS 18 (Ramdisk)" "Step 2: Partition" "Step 3: OS Install")
        if [[ $device_mode == "Normal" ]]; then
            menu_items+=("Reinstall App" "Boot iOS 4.3.x")
        fi
        menu_items+=("Go Back")
        menu_print_info
        print "* ipad6-ipados18: Dualboot iPad 6 to iPadOS 18"
        print "* Based on: https://github.com/asdfugil/ipad6-ipados18"
        echo
        print " > Main Menu > ipad6-ipados18"
        input "Select an option:"
        select_option "${menu_items[@]}"
        selected="${menu_items[$?]}"
        case $selected in
            "Step 1: Setup iPadOS 18 (Ramdisk)" ) menu_ipsw_ipad6_ipados18;;
            "Step 2: Partition" ) mode="device_fourthree_step2";;
            "Step 3: OS Install" ) mode="device_fourthree_step3";;
            "Reinstall App" ) mode="device_fourthree_app";;
            "Boot iOS 4.3.x" ) mode="device_fourthree_boot";;
            "Go Back" ) back=1;;
        esac
    done
}

menu_ipsw_ipad6_ipados18() {
    local menu_items
    local selected
    local back
    local newpath
    local nav
    local start="(*) Start Setup"
    local base_text
    local target_text

    nav=" > Main Menu > ipad6-ipados18 > Step 1: Setup iPadOS 18 (Ramdisk)"

    while [[ -z "$mode" && -z "$back" ]]; do
        if [[ $device_type == "iPad7,5" ]]; then
            device_type_special="iPad7,11"
            device_model_special="j171"
        else
            device_type_special="iPad7,12"
            device_model_special="j172"
        fi
        device_target_vers="18.7.10"
        device_target_build="22H374"
        target_text="iPad 7-$device_target_vers"
        ipsw_latest_set

        menu_print_info
        print "* Only select unmodified IPSW for the selection. Do not select custom IPSWs"
        echo

        if [[ -n $ipsw_path ]]; then
            print "* Selected Target IPSW ($target_text): $ipsw_path.ipsw"
        else
            print "* Select Target IPSW ($target_text) to continue"
        fi
        echo
        menu_items=("Select Target IPSW" "Download Target IPSW")
        if [[ -n $ipsw_path ]]; then
            menu_items+=("$start")
        fi
        menu_items+=("Go Back")

        print "$nav"
        input "Select an option:"
        select_option "${menu_items[@]}"
        selected="${menu_items[$?]}"
        case $selected in
            "$start" ) mode="device_ipad6_ipados18_step1";;
            "Select Target IPSW" ) menu_ipsw_browse "special";;
            "Download Target IPSW" ) ipsw_download "../iPad_10.2_${device_target_vers}_${device_target_build}_Restore" special;;
            "Go Back" )
                back=1

                ipsw_path=
                ipsw_base_path=
                device_type_special=
            ;;
        esac
    done
}
