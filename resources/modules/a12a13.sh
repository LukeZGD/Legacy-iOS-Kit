# a12a13 module is heavily based on surrealra1n, credits to pwnerblu and contributors

a12a13_values_init() {
    case "$device_type" in
        iPhone11,8 )
            REFER="iphone11b"
            REFER2="n841"
            AOP14="aopfw-iphone11baop.im4p"
            AOP="aopfw-iphone11baop.RELEASE.im4p"
            ISP="adc-petra-n84.im4p"
            GFX="armfw_g11p.im4p"
            MTFW="N841_Multitouch.im4p"
            KERNEL2="kernelcache.release.iphone11x"
            CALLAN="N841_CallanFirmware.im4p"
            HAPTICASSET="N841_HapticAssets.im4p"
            WIRELESS="WirelessPower.iphone11b.im4p"
        ;;

        iPad11,[1234] )
            REFER="ipad11"
            AOP14="aopfw-ipad11aop.im4p"
            AOP="aopfw-ipad11aop.RELEASE.im4p"
            ISP="adc-petra-j2x.im4p"
            GFX="armfw_g11p.im4p"
            KERNEL2="kernelcache.release.ipad11x"

            case "$device_type" in
                iPad11,1 )
                    REFER2="j210"
                    MTFW="J210_Multitouch.im4p"
                ;;
                iPad11,2 )
                    REFER2="j210"
                    MTFW="J211_Multitouch.im4p"
                ;;
                iPad11,3 )
                    REFER2="j217"
                    MTFW="J217_Multitouch.im4p"
                ;;
                iPad11,4 )
                    REFER2="j217"
                    MTFW="J218_Multitouch.im4p"
                ;;
            esac
        ;;

        iPhone11,[246] )
            REFER="iphone11"
            AOP14="aopfw-iphone11aop.im4p"
            AOP="aopfw-iphone11aop.RELEASE.im4p"
            ISP="adc-petra-d3x.im4p"
            GFX="armfw_g11p.im4p"
            KERNEL2="kernelcache.release.iphone11x"

            case "$device_type" in
                iPhone11,2 )
                    REFER2="d321"
                    CALLAN="D321_CallanFirmware.im4p"
                    HAPTICASSET="D321_HapticAssets.im4p"
                    MTFW="D321_Multitouch.im4p"
                ;;
                iPhone11,4 )
                    REFER2="d331"
                    CALLAN="D331_CallanFirmware.im4p"
                    HAPTICASSET="D331_HapticAssets.im4p"
                    MTFW="D331_Multitouch.im4p"
                ;;
                iPhone11,6 )
                    REFER2="d331p"
                    CALLAN="D331P_CallanFirmware.im4p"
                    HAPTICASSET="D331P_HapticAssets.im4p"
                    MTFW="D331P_Multitouch.im4p"
                ;;
            esac

            WIRELESS="WirelessPower.iphone11.im4p"
        ;;

        iPhone12,[2358] )
            REFER="iphone12"
            AOP14="aopfw-iphone12aop.im4p"
            AOP="aopfw-iphone12aop.RELEASE.im4p"
            IOFW="SmartIOFirmware_ASCv2.im4p"
            IOFW13="SmartIOFirmwareT8030.im4p"
            GFX="armfw_g12p.im4p"
            ANE="h12_ane_fw_metis.im4p"
            AVE="AppleAVE2FW_H12.im4p"
            AVE13="AppleAVE2FW.im4p"
            KERNEL2="kernelcache.release.iphone12x"

            case "$device_type" in
                iPhone12,1 )
                    REFER="iphone12b"
                    REFER2="n104"
                    AOP14="aopfw-iphone12baop.im4p"
                    AOP="aopfw-iphone12baop.RELEASE.im4p"
                    ISP="adc-zelus-n104.im4p"
                    CALLAN="N104_AudioCodecFirmware.im4p"
                    HAPTICASSET="N104_HapticAssets.im4p"
                    MTFW="N104_Multitouch.im4p"
                    LEAPHAPTIC="N104_LeapHapticsFirmware.im4p"
                    WIRELESS="WirelessPower.iphone12b.im4p"
                ;;
                iPhone12,[35] )
                    ISP="adc-zelus-d4x.im4p"
                    WIRELESS="WirelessPower.iphone12.im4p"

                    if [[ $device_type == iPhone12,3 ]]; then
                        REFER2="d421"
                        CALLAN="D421_AudioCodecFirmware.im4p"
                        HAPTICASSET="D421_HapticAssets.im4p"
                        MTFW="D421_Multitouch.im4p"
                        LEAPHAPTIC="D421_LeapHapticsFirmware.im4p"
                    else # iPhone12,5
                        REFER2="d431"
                        CALLAN="D431_AudioCodecFirmware.im4p"
                        HAPTICASSET="D431_HapticAssets.im4p"
                        MTFW="D431_Multitouch.im4p"
                        LEAPHAPTIC="D431_LeapHapticsFirmware.im4p"
                    fi
                ;;
                iPhone12,8 )
                    REFER="iphone12c"
                    REFER2="d79"
                    AOP14="aopfw-iphone12caop.im4p"
                    AOP="aopfw-iphone12caop.RELEASE.im4p"
                    ISP="adc-zelus-d79.im4p"
                    CALLAN="D79_AudioCodecFirmware.im4p"
                    MTFW="D79_Multitouch.im4p"
                    WIRELESS="WirelessPower.iphone12c.im4p"
                ;;
            esac
        ;;
    esac

    # Firmware components shared by all supported devices.
    IOFW="SmartIOFirmware_ASCv2.im4p"
    ANE="${ANE:-h11_ane_fw_quin.im4p}"
    AVE="${AVE:-AppleAVE2FW_H11.im4p}"

    IBSS="iBSS.$REFER2.RELEASE.im4p"
    IBEC="iBEC.$REFER2.RELEASE.im4p"
    DEVICETREE="DeviceTree.${device_model}ap.im4p"
    KERNEL="kernelcache.release.$REFER"

    # case $device_type in
    #     iPad11,1 | iPhone11,[28] | iPhone12,[13] ) base_identity=0;;
    #     iPad11,2 | iPhone11,4 | iPhone12,5       ) base_identity=1;;
    #     iPad11,3 | iPhone11,6                    ) base_identity=2;;
    #     iPad11,4                                 ) base_identity=3;;
    # esac
}

device_a12a13_ipsw_tethered() {
    ipsw_custom="../${ipsw_prefix}_${device_target_vers}_${device_target_build}_CustomT"
    boot_folder="../saved/${device_type}/boot_${device_target_vers}_${device_target_build}"

    if [[ -s "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi

    if (( target_vers_maj >= 16 )); then
        python3_init
    fi

    # prepare folders
    mkdir -p $boot_folder tmp1/ tmp2/

    # extract ipsws
    log "Extracting target IPSW: $ipsw_path.ipsw"
    file_extract "$ipsw_path.ipsw" tmp1/
    log "Extracting base IPSW: $ipsw_base_path.ipsw"
    file_extract "$ipsw_base_path.ipsw" tmp2/ exclude "*.aea"
    chmod 644 tmp1/*.plist tmp2/*.plist

    # prepare target keys
    device_fw_key_check

    log "Starting iBSS patch"
    local iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "iBSS") | .iv')
    local key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "iBSS") | .key')
    log "Got iBSS ivkey: ${iv}${key}"
    "$dir/img4" -i tmp1/Firmware/dfu/$IBSS -o iBSS.raw -k ${iv}${key}
    if (( target_vers_maj >= 15 )) || [[ $device_proc == 13 && $target_vers_maj == 14 ]]; then
        log "iBootPatch patches"
        "$dir/iBootPatch" iBSS.raw $boot_folder/iBSS.patch
        "$dir/iBootPatch" -v -b "-v" iBSS.raw iBSS.patchboot
    else
        log "iBoot64Patcher patches"
        "$dir/iBoot64Patcher" iBSS.raw $boot_folder/iBSS.patch
        "$dir/iBoot64Patcher" iBSS.raw iBSS.patchboot -b "-v"
    fi
    "$dir/iBootpatch2" iBSS.patchboot $boot_folder/iBSS.boot
    "$dir/img4" -i $boot_folder/iBSS.patch -o tmp2/Firmware/dfu/$IBEC -A -T ibec

    log "Extract BuildManifests"
    file_extract_from_archive "$ipsw_base_path.ipsw" BuildManifest.plist
    mv BuildManifest.plist bm_base.plist
    file_extract_from_archive "$ipsw_path.ipsw" BuildManifest.plist
    mv BuildManifest.plist bm_target.plist
    chmod 644 *.plist

    local restored="restored_update"
    local rtype="Upgrade"
    if (( target_vers_maj >= 16 )) || [[ $target_vers_maj == 13 || $device_target_build == "18A5342e" ]]; then
        restored="restored_external"
        rtype="Erase"
    fi
    log "restored: $restored"
    ipsw_get_ramdisk_identity Erase bm_base.plist
    base_identity=$target_identity
    log "Base identity: $base_identity"
    ipsw_get_ramdisk_identity $rtype bm_target.plist
    log "Target identity: $target_identity"

    local fs_dmg_name="$($PlistBuddy -c "Print BuildIdentities:$target_identity:Manifest:OS:Info:Path" bm_target.plist | tr -d '"')"
    local fs_dmg_name_18="$($PlistBuddy -c "Print BuildIdentities:$base_identity:Manifest:OS:Info:Path" bm_base.plist | tr -d '"')"
    local ramdisk_dmg_name="$($PlistBuddy -c "Print BuildIdentities:$target_identity:Manifest:RestoreRamDisk:Info:Path" bm_target.plist | tr -d '"')"
    local ramdisk_dmg_name_18="$($PlistBuddy -c "Print BuildIdentities:$base_identity:Manifest:RestoreRamDisk:Info:Path" bm_base.plist | tr -d '"')"

    # ios 16 stuff
    local cryptex_app cryptex_app_18 cryptex_os cryptex_os_18
    cryptex_app_18="$($PlistBuddy -c "Print BuildIdentities:$base_identity:Manifest:Cryptex1,AppOS:Info:Path" bm_base.plist | tr -d '"')"
    cryptex_os_18="$($PlistBuddy -c "Print BuildIdentities:$base_identity:Manifest:Cryptex1,SystemOS:Info:Path" bm_base.plist | tr -d '"')"
    if (( target_vers_maj >= 16 )); then
        cryptex_app="$($PlistBuddy -c "Print BuildIdentities:$target_identity:Manifest:Cryptex1,AppOS:Info:Path" bm_target.plist | tr -d '"')"
        cryptex_os="$($PlistBuddy -c "Print BuildIdentities:$target_identity:Manifest:Cryptex1,SystemOS:Info:Path" bm_target.plist | tr -d '"')"
        log "Modify base BuildManifest with KERNEL2: $KERNEL2"
        env KERNEL2="$KERNEL2" IDENTITY="$base_identity" python3 <<'PY'
import os
import plistlib

with open("tmp2/BuildManifest.plist", "rb") as f:
    plist = plistlib.load(f)

identity = int(os.environ["IDENTITY"])

plist["BuildIdentities"][identity]["Manifest"]["KernelCache"]["Info"]["Path"] = os.environ["KERNEL2"]

with open("tmp2/BuildManifest.plist", "wb") as f:
    plistlib.dump(plist, f)
PY
    else
        touch tmp2/$cryptex_app_18
        touch tmp2/$cryptex_os_18
    fi

    log "Transferring stuff over from target to base"
    cp -v tmp1/Firmware/AOP/$AOP14 tmp2/Firmware/AOP/$AOP
    cp -v tmp1/Firmware/agx/$GFX tmp2/Firmware/agx/$GFX
    cp -v tmp1/Firmware/ane/$ANE tmp2/Firmware/ane/$ANE
    cp -v tmp1/Firmware/isp_bni/$ISP tmp2/Firmware/isp_bni/$ISP
    if [[ $device_type == "iPhone"* ]]; then
        cp -v tmp1/Firmware/$CALLAN tmp2/Firmware/$CALLAN
        cp -v tmp1/Firmware/WirelessPower/$WIRELESS tmp2/Firmware/WirelessPower/$WIRELESS
    fi
    case $device_type in
        iPhone12,8 ) :;;
        iPhone1[12],* ) cp -v tmp1/Firmware/$HAPTICASSET tmp2/Firmware/$HAPTICASSET;;
    esac
    cp -v tmp1/Firmware/all_flash/$DEVICETREE tmp2/Firmware/all_flash/$DEVICETREE
    if [[ $target_vers_maj == 13 ]]; then
        cp -v tmp1/Firmware/$IOFW13 tmp2/Firmware/$IOFW
        cp -v tmp1/Firmware/ave/$AVE13 tmp2/Firmware/ave/$AVE
    else
        cp -v tmp1/Firmware/$IOFW tmp2/Firmware/$IOFW
        cp -v tmp1/Firmware/ave/$AVE tmp2/Firmware/ave/$AVE
        cp -v tmp1/Firmware/$fs_dmg_name.root_hash tmp2/Firmware/$fs_dmg_name_18.root_hash
        cp -v tmp1/Firmware/$fs_dmg_name.mtree tmp2/Firmware/$fs_dmg_name_18.mtree
    fi
    if (( target_vers_maj >= 16 )); then
        case $device_type in
            iPhone11,[246] ) log "Using latest MTFW";;
            * ) cp -v tmp1/Firmware/$MTFW tmp2/Firmware/$MTFW;; # copy MTFW for target iOS
        esac
    else
        cp -v tmp1/Firmware/$MTFW tmp2/Firmware/$MTFW # copy MTFW for target iOS
    fi
    if [[ $device_type == "iPhone12,"* ]]; then
        if [[ $device_type != "iPhone12,8" ]]; then
            cp -v tmp1/Firmware/$LEAPHAPTIC tmp2/Firmware/$LEAPHAPTIC
        fi
        cp -v tmp1/Firmware/pmp/$PMP tmp2/Firmware/pmp/$PMP
    fi

    log "Transferring rootfs, this will take a while"
    cp -v tmp1/$fs_dmg_name tmp2/$fs_dmg_name_18 # replace rootfs in the IPSW
    cp -v tmp1/Firmware/$fs_dmg_name.trustcache tmp2/Firmware/$fs_dmg_name_18.trustcache
    cp -v tmp1/Firmware/$ramdisk_dmg_name.trustcache tmp2/Firmware/$ramdisk_dmg_name_18.trustcache
    if (( target_vers_maj >= 16 )); then
        log "Transferring cryptex stuff, this will take a while"
        cp -v tmp1/$cryptex_os tmp2/$cryptex_os_18
        cp -v tmp1/$cryptex_app tmp2/$cryptex_app_18
        cp -v tmp1/Firmware/$cryptex_os.trustcache tmp2/Firmware/$cryptex_os_18.trustcache
        cp -v tmp1/Firmware/$cryptex_os.root_hash tmp2/Firmware/$cryptex_os_18.root_hash
        cp -v tmp1/Firmware/$cryptex_app.trustcache tmp2/Firmware/$cryptex_app_18.trustcache
        cp -v tmp1/Firmware/$cryptex_app.root_hash tmp2/Firmware/$cryptex_app_18.root_hash
    fi

    log "Starting kernel patch"
    "$dir/img4" -i tmp1/$KERNEL -o kernel.raw
    case $target_vers_maj in
        13 ) "$dir/Kernel64Patcher" kernel.raw kernelboot.patch -b13 -n;;
        14 ) "$dir/Kernel64Patcher" kernel.raw kernelboot.patch -b;;
        15 ) "$dir/Kernel64Patcher" kernel.raw kernelboot.patch -we;;
        16 ) "$dir/Kernel64Patcher" kernel.raw kernelboot.patch -we -d;;
    esac
    "$dir/kerneldiff" kernel.raw kernelboot.patch kernelboot.diff
    rm -f tmp2/$KERNEL
    if (( target_vers_maj >= 16 )); then
        "$dir/img4" -i kernelboot.patch -o tmp2/$KERNEL2 -A -T krnl -J
        cp -v tmp1/$KERNEL tmp2/$KERNEL
    else
        "$dir/img4" -i tmp1/$KERNEL -o tmp2/$KERNEL -T krnl -J -P kernelboot.diff
    fi

    log "Starting ramdisk stuff"
    "$dir/img4" -i tmp1/$ramdisk_dmg_name -o ramdisk.raw
    mkdir -p rd
    7z x ramdisk.raw -o./rd/ -snld
    mv rd/*/* rd/
    rm -rf rd/*RamDisk/ ramdisk.raw
    # chmod 644 rd/usr/lib/* rd/usr/lib/system/* rd/usr/lib/swift/* rd/usr/lib/log/* rd/usr/lib/updaters/* rd/System/Library/CoreServices/*
    # chmod 755 rd/sbin/*

    log "asr patch"
    cp -v rd/usr/sbin/asr asr
    "$dir/asr64_patcher" asr asr_patched
    "$dir/ldid" -e asr > ents.plist
    "$dir/ldid" -Sents.plist asr_patched
    chmod +x asr_patched
    cp -v asr_patched rd/usr/sbin/asr
    if (( target_vers_maj >= 14 )); then
        log "libimg4 patch"
        cp -v rd/usr/lib/libimg4.dylib libimg4.dylib
        "$dir/libimg4_patcher" libimg4.dylib libimg4.patch
        "$dir/ldid" -Sents.plist libimg4.patch
        chmod +x libimg4.patch
        cp -v libimg4.patch rd/usr/lib/libimg4.dylib
    fi

    local ramdisk_download_name ramdisk_url
    if [[ $target_vers_maj == 16 ]]; then
        ramdisk_download_name="098-08863-001.dmg"
        ramdisk_url="https://updates.cdn-apple.com/2022FallFCS/fullrestores/012-65861/0A0400A0-2174-4D49-91B7-43FC9DE24272/iPhone10,3,iPhone10,6_16.0_20A362_Restore.ipsw"
    elif [[ $target_vers_maj == 15 ]]; then
        ramdisk_download_name="018-79907-001.dmg"
        if [[ $restored == "restored_update" ]]; then
            ramdisk_download_name="018-80166-001.dmg"
        fi
        ramdisk_url="https://updates.cdn-apple.com/2021FallFCS/fullrestores/002-02910/AF984499-D03A-43E7-9472-6D16BA756E5E/iPhone10,3,iPhone10,6_15.0_19A346_Restore.ipsw"
    elif [[ $target_vers_maj == 14 ]]; then
        ramdisk_download_name="048-58904-639.dmg"
        if [[ $restored == "restored_update" ]]; then
            ramdisk_download_name="048-58813-634.dmg"
        fi
        ramdisk_url="https://updates.cdn-apple.com/2020SummerFCS/fullrestores/001-46617/B62CA88B-EB85-4A5A-9440-7E0B90B02006/iPhone10,3,iPhone10,6_14.0_18A373_Restore.ipsw"
    else # iOS 13
        ramdisk_download_name="048-96245-001.dmg"
        if [[ $restored == "restored_update" ]]; then
            ramdisk_download_name="048-96454-001.dmg"
        fi
        ramdisk_url="https://updates.cdn-apple.com/2019FallFCS/fullrestores/061-08721/B905C96C-C875-11E9-8C18-F4CC329DFA63/iPhone10,3,iPhone10,6_13.0_17A577_Restore.ipsw"
    fi
    log "restored patch"
    if (( target_vers_maj >= 16 )); then
        if [[ -s ../saved/$device_type/$ramdisk_download_name ]]; then
            cp -v ../saved/$device_type/$ramdisk_download_name .
        else
            "$dir/pzb" -g $ramdisk_download_name $ramdisk_url
            cp -v $ramdisk_download_name ../saved/$device_type/
        fi
        if [[ ! -s $ramdisk_download_name ]]; then
            error "Failed to download ramdisk for restored patch. Please run the script again"
        fi
        "$dir/img4" -i $ramdisk_download_name -o ramdisk2.raw
        "$dir/hfsplus" ramdisk2.raw extract usr/local/bin/$restored restored_external
        "$dir/restoredpatcher" restored_external restored_patch -c # patch cryptex1 install validation
        case $device_type in
            iPhone12,[135] )
                mv -v restored_patch restored_patc
                "$dir/ipx_restored_patcher" restored_patc restored_patch
            ;;
        esac
        "$dir/ldid" -e restored_external > ents.plist
        "$dir/ldid" -Sents.plist restored_patch
        chmod +x restored_patch
        cp -v restored_patch rd/usr/local/bin/$restored

    elif [[ $device_type == "iPhone11,"* || $device_type == "iPhone12,"* ]] && [[ $device_type != "iPhone12,8" ]]; then
        if [[ -s ../saved/$device_type/$ramdisk_download_name ]]; then
            cp -v ../saved/$device_type/$ramdisk_download_name .
        else
            "$dir/pzb" -g $ramdisk_download_name $ramdisk_url
            cp -v $ramdisk_download_name ../saved/$device_type/
        fi
        if [[ ! -s $ramdisk_download_name ]]; then
            error "Failed to download ramdisk for restored patch. Please run the script again"
        fi
        "$dir/img4" -i $ramdisk_download_name -o ramdisk2.raw
        "$dir/hfsplus" ramdisk2.raw extract usr/local/bin/$restored restored_external
        "$dir/ipx_restored_patcher" restored_external restored_patch
        "$dir/ldid" -e restored_external > ents.plist
        "$dir/ldid" -Sents.plist restored_patch
        chmod +x restored_patch
        cp -v restored_patch rd/usr/local/bin/$restored
    fi

    log "trustcache patch"
    "$dir/img4" -i tmp1/Firmware/$ramdisk_dmg_name.trustcache -o trustcache.raw
    "$dir/trustcache" append trustcache.raw asr_patched
    if (( target_vers_maj >= 16 )); then
        "$dir/trustcache" append trustcache.raw restored_patch
        "$dir/trustcache" append trustcache.raw libimg4.patch
    else
        if [[ $device_type != "iPhone12,8" ]]; then
            "$dir/trustcache" append trustcache.raw restored_patch
        fi
        if (( target_vers_maj >= 14 )); then
            "$dir/trustcache" append trustcache.raw libimg4.patch
        fi
    fi
    "$dir/img4" -i trustcache.raw -o tmp2/Firmware/$ramdisk_dmg_name_18.trustcache -A -T rtsc

    log "Finalizing"
    # genisoimage -D -V "RamDisk" -no-pad -r -apple -o ramdisk.iso rd/*
    # "$dir/dmg" dmg ramdisk.iso ramdisk.raw

    pushd rd
    tar -cf ../ramdisk.tar .
    popd
    cp -v ../resources/image.raw ramdisk.raw
    "$dir/hfsplus" ramdisk.raw untar ramdisk.tar # fails here

    "$dir/img4" -i ramdisk.raw -o tmp2/$ramdisk_dmg_name_18 -A -T rdsk
    rm -rf tmp1/
    pushd tmp2
    zip -r0 ../$ipsw_custom.ipsw *
    popd
    mv tmp2/ $ipsw_custom/
}

device_a12a13_restore_tethered() {
    device_enter_mode pwnDFU

    device_a12a13_ipsw_tethered

    if [[ $device_pwnrec != 1 ]]; then
        log "Sending iBSS..."
        $primepwn $boot_folder/iBSS.patch
    fi
    device_find_mode Recovery

    ipsw_path="$ipsw_custom"
    if (( target_vers_maj >= 16 )); then
        restore_latest
    else
        device_target_vers="$device_latest_vers"
        device_target_build="$device_latest_build"
        shsh_save apnonce
        restore_futurerestore --skip-cryptex --skip-ibec
    fi
}

device_justboot_a12a13() {
    if [[ -z $device_selectedboot && -n $device_rd_build ]]; then
        local boot_matches=(../saved/$device_type/boot_*$device_rd_build)
        if [[ ! -d ${boot_matches[0]} ]]; then
            error "Unable to find boot folder for $device_type-$device_rd_build"
        fi
        device_selectedboot=$(basename ${boot_matches[0]})
        log "Found boot folder: $device_selectedboot"
    fi
    device_enter_mode pwnDFU
    $primepwn ../saved/$device_type/$device_selectedboot/iBSS.boot
}

menu_justboot_a12a13() {
    local menu_items
    local selected
    local back
    local boot_folder="../saved/$device_type"
    local boot_files

    while [[ -z "$mode" && -z "$back" ]]; do
        menu_print_info
        boot_files=()
        menu_items=()

        for b in "$boot_folder"/boot_*; do
            [[ -d $b ]] || continue
            boot_files+=("${b##*/}")
        done

        if [[ ${#boot_files[@]} == 0 ]]; then
            print "* No boot files"
        else
            print "* Boot files list (saved/$device_type):"
            for b in "${boot_files[@]}"; do
                menu_items+=("$b")
            done
        fi

        menu_items+=("Go Back")
        echo
        print " > Main Menu > Just Boot"
        input "Select option to boot:"
        select_option "${menu_items[@]}"
        selected="${menu_items[$?]}"
        case $selected in
            "Go Back" ) back=1;;
            * )
                device_selectedboot="$selected"
                print "* The selected boot file $device_selectedboot will be used for Just Boot."
                select_yesno
                if [[ $? != 1 ]]; then
                    device_selectedboot=
                    continue
                fi
                mode="device_justboot_a12a13"
            ;;
        esac
    done
}


menu_ipsw_a12a13_tethered() {
    local menu_items
    local selected
    local back
    local newpath
    local nav
    local start="(*) "
    local base_text
    local target_text

    a12a13_values_init
    check_vers="$device_latest_vers"
    base_vers="$device_latest_vers"
    device_target_tethered=1
    if [[ $2 == "ipsw" ]]; then
        nav=" > Main Menu > Misc Utilities > Create Custom IPSW > $1"
        start+="Create IPSW"
    else
        nav=" > Main Menu > Restore/Downgrade > $1"
        start+="Start Restore"
    fi

    while [[ -z "$mode" && -z "$back" ]]; do
        ipsw_latest_set

        menu_print_info
        print "* Only select unmodified IPSW for the selection. Do not select custom IPSWs"
        echo

        local lo="14.0 beta 4"
        local hi="16.0.3"
        [[ $device_proc == 13 ]] && lo="13.4"

        if [[ -n $ipsw_path ]]; then
            print "* Selected Target IPSW: $ipsw_path.ipsw"
            print "* Target Version: $device_target_vers-$device_target_build"
            if [[ $ipsw_validate == 0 ]]; then
                print "* Selected Target IPSW is validated"
            else
                warn "Selected Target IPSW failed validation, proceed with caution"
            fi
            if [[ ( $target_vers_maj == 14 || $target_vers_maj == 15 ) && $device_target_build != "18A5342e" ]]; then
                case $device_proc in
                    12 ) warn "Make sure the device has been restored and activated on iOS 14 beta 4 before proceeding.";;
                    13 ) warn "Make sure the device has been restored and activated on iOS 13.x or iOS 14 beta 4 before proceeding.";;
                esac
                print "* This step is required for the tethered iOS 14 or 15 installation to be usable."
            elif (( target_vers_maj > 16 || target_vers_maj < 13 )) ||    # iOS 12 and 17+
                 (( target_vers_maj == 16 && target_vers_min > 0 )) ||    # iOS 16.1+
                 (( target_vers_maj == 13 && target_vers_min < 4 )); then # iOS 13.3.1-
                warn "The selected IPSW version is not supported. Select a supported IPSW to continue."
                print "* Supported iOS versions: $lo to $hi"
            fi
        else
            print "* Select Target IPSW to continue"
            print "* Supported iOS versions: $lo to $hi"
        fi
        echo
        local text2="(iOS $base_vers)"
        if [[ -n $ipsw_base_path ]]; then
            print "* Selected Base IPSW $text2: $ipsw_base_path.ipsw"
            if [[ $ipsw_base_validate == 0 ]]; then
                print "* Selected Base IPSW is validated"
            else
                warn "Selected Base IPSW failed validation, proceed with caution"
            fi
            echo
        else
            print "* Select Base IPSW $text2 to continue"
            echo
        fi
        warn "This is a tethered downgrade. Not recommended unless you know what you are doing."
        print "* For more info, go to: https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/A12-A13-Tethered"
        print "* a12a13 module is heavily based on surrealra1n, credits to pwnerblu and contributors"
        echo

        menu_items=("Select Target IPSW" "Select Base IPSW")
        if [[ -n $device_base_vers && -z $ipsw_base_path ]]; then
            menu_items+=("Download Base IPSW")
        fi
        if [[ -n $ipsw_path && -n $ipsw_base_path ]]; then
            if [[ $device_proc == 13 ]]; then
                case $device_target_vers in
                    13.[4567]* | 1[45].* | 16.0* ) menu_items+=("$start");;
                esac
            else
                case $device_target_vers in
                    1[45].* | 16.0* ) menu_items+=("$start");;
                esac
            fi
        fi
        menu_items+=("Go Back")

        print "$nav"
        input "Select an option:"
        select_option "${menu_items[@]}"
        selected="${menu_items[$?]}"
        case $selected in
            "(*) Create IPSW"    ) mode="device_a12a13_ipsw_tethered";;
            "$start"             ) mode="device_a12a13_restore_tethered";;
            "Select Target IPSW" ) menu_ipsw_browse;;
            "Select Base IPSW"   ) menu_ipsw_browse "base";;
            "Go Back" )
                back=1

                ipsw_path=
                ipsw_base_path=
                device_type_special=
                check_vers=
                base_vers=
                device_target_tethered=
            ;;
        esac
    done
}
