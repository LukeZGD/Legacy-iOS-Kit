ipad6_ipados18_ramdisk() {
    local loc="../saved/ipad6-ipados18"
    local comps=("iBSS" "iBEC" "DeviceTree" "Kernelcache" "RestoreRamdisk" "Trustcache")
    local name
    local iv
    local key
    local path
    local url
    local decrypt
    local opt
    local build_id="21H16"

    mkdir -p $loc

    local ramdisk_path="$loc/ramdisk_$build_id"
    device_target_build="$build_id"
    device_fw_key_check
    ipsw_get_url $build_id
    mkdir -p $ramdisk_path
    rm -f $ramdisk_path/*.img4 $ramdisk_path/iBEC.im4p $ramdisk_path/iBSS.im4p

    for getcomp in "${comps[@]}"; do
        name=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .filename')
        iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .iv')
        key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .key')
        case $getcomp in
            "iBSS" | "iBEC" ) path="Firmware/dfu/";;
            "DeviceTree" ) path="Firmware/all_flash/";;
            "Trustcache" ) path="Firmware/";;
            * ) path="";;
        esac
        if [[ -z $name ]]; then
            local hwmodel
            ipsw_hwmodel_set
            hwmodel="$ipsw_hwmodel"
            case $getcomp in
                "iBSS" | "iBEC"  ) name="$getcomp.$hwmodel.RELEASE.im4p";;
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
            file_download https://github.com/LukeZGD/Legacy-iOS-Kit-Keys/releases/download/a/ramdisk1.dmg ramdisk1.dmg 32f93cac47fb91dbc54e85131f950f742dfc947e
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
                $bspatch $getcomp.dec $getcomp.orig ../resources/sshrd/ipad6-ipados18/$getcomp.patch
            ;;
            "Kernelcache" )
                reco+="rkrn"
                reco+=" -P ../resources/sshrd/ipad6-ipados18/kc.bpatch -J"
            ;;
            "DeviceTree" )
                reco+="rdtr"
                if [[ $device_ramdisk_ios8 == 1 ]]; then
                    reco+=" -A"
                    mv $getcomp.orig $getcomp.orig0
                    "$dir/img4" -i $getcomp.orig0 -o $getcomp.orig -k ${iv}${key}
                fi
            ;;
            "Trustcache" ) reco+="rtsc";;
            "RestoreRamdisk" ) reco+="rdsk -A";;
        esac
        "$dir/img4" $reco
    done

    mv iBSS.img4 iBSS.im4p
    mv iBEC.img4 iBEC.im4p
    iBSS="iBSS"
    iBEC="iBEC"

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

    menu_ramdisk $build_id
}
