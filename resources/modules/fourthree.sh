ipsw_prepare_fourthree() {
    local comps=("AppleLogo" "DeviceTree" "iBoot" "RecoveryMode")
    local saved_path="../saved/$device_type/8L1"
    local bpatch="../resources/patch/fourthree/$device_type/6.1.3"
    local name
    local iv
    local key
    if [[ $ipsw_fourthree != 1 ]]; then
        return
    fi
    log "Preparing IPSW for FourThree"
    ipsw_get_url 8L1
    url="$ipsw_url"
    device_fw_key_check
    device_fw_key_check temp 8L1
    mkdir -p $all_flash Downgrade $saved_path
    log "Extracting files"
    file_extract_from_archive "$ipsw_path.ipsw" $all_flash/manifest
    mv manifest $all_flash
    file_extract_from_archive temp.ipsw Downgrade/RestoreDeviceTree
    log "RestoreDeviceTree"
    iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "DeviceTree") | .iv')
    key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "DeviceTree") | .key')
    "$dir/xpwntool" RestoreDeviceTree RestoreDeviceTree.dec -iv $iv -k $key -decrypt
    $bspatch RestoreDeviceTree.dec Downgrade/RestoreDeviceTree $bpatch/RestoreDeviceTree.patch
    for getcomp in "${comps[@]}"; do
        name=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "'$getcomp'") | .filename')
        iv=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "'$getcomp'") | .iv')
        key=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "'$getcomp'") | .key')
        path="$all_flash/"
        log "$getcomp"
        if [[ $vers == "$device_base_vers" ]]; then
            file_extract_from_archive "$ipsw_base_path.ipsw" ${path}$name
        elif [[ -e $saved_path/$name ]]; then
            cp $saved_path/$name .
        else
            download_with_pzb "$url" "${path}$name" "$name"
            cp $name $saved_path/
        fi
        "$dir/xpwntool" $name $getcomp.dec -iv $iv -k $key -decrypt
        case $getcomp in
            "AppleLogo" )
                getcomp="applelogo"
                mv AppleLogo.dec applelogo.dec
                echo "0000010: 6267" | xxd -r - applelogo.dec
                echo "0000020: 6267" | xxd -r - applelogo.dec
            ;;
            "DeviceTree" )
                echo "0000010: 6272" | xxd -r - DeviceTree.dec
                echo "0000020: 6272" | xxd -r - DeviceTree.dec
            ;;
            "RecoveryMode" )
                getcomp="recoverymode"
                mv RecoveryMode.dec recoverymode.dec
                echo "0000010: 6263" | xxd -r - recoverymode.dec
                echo "0000020: 6263" | xxd -r - recoverymode.dec
            ;;
            "iBoot" )
                mv iBoot.dec iBoot.dec0
                $bspatch iBoot.dec0 iBoot.dec $bpatch/iBoot.${device_model}ap.RELEASE.patch
                #"$dir/xpwntool" iBoot.dec0 iBoot.dec2
                #"$dir/iBoot32Patcher" iBoot.dec2 iBoot.patched --rsa -b "rd=disk0s3 -v amfi=0xff cs_enforcement_disable=1 pio-error=0"
                #"$dir/xpwntool" iBoot.patched iBoot.dec -t iBoot.dec0
                #echo "0000010: 626F" | xxd -r - iBoot.dec
                #echo "0000020: 626F" | xxd -r - iBoot.dec
            ;;
        esac
        mv $getcomp.dec $path/${getcomp}B.img3
        echo "${getcomp}B.img3" >> $path/manifest
    done
    log "Add files to IPSW"
    zip -r0 temp.ipsw $all_flash/* Downgrade/*
}

ipsw_prepare_fourthree_part2() {
    device_fw_key_check base
    local saved_path="../saved/$device_type/$device_base_build"
    local bpatch="../resources/patch/fourthree/$device_type/$device_base_vers"
    local iv
    local key
    mkdir -p $saved_path
    log "Preparing components for FourThree dualboot"
    if [[ ! -s $saved_path/Kernelcache ]]; then
        log "Kernelcache"
        iv=$(echo $device_fw_key_base | $jq -j '.keys[] | select(.image == "Kernelcache") | .iv')
        key=$(echo $device_fw_key_base | $jq -j '.keys[] | select(.image == "Kernelcache") | .key')
        file_extract_from_archive "$ipsw_base_path.ipsw" kernelcache.release.$device_model
        "$dir/xpwntool" kernelcache.release.$device_model kernelcache.dec -iv $iv -k $key
        $bspatch kernelcache.dec kernelcache.patched $bpatch/kernelcache.release.patch
        "$dir/xpwntool" kernelcache.patched kernelcachb -t kernelcache.release.$device_model -iv $iv -k $key
        "$dir/xpwntool" kernelcachb $saved_path/Kernelcache -iv $iv -k $key -decrypt
    fi
    if [[ ! -s $saved_path/LLB ]]; then
        log "LLB"
        iv=$(echo $device_fw_key_base | $jq -j '.keys[] | select(.image == "LLB") | .iv')
        key=$(echo $device_fw_key_base | $jq -j '.keys[] | select(.image == "LLB") | .key')
        file_extract_from_archive "$ipsw_base_path.ipsw" $all_flash/LLB.${device_model}ap.RELEASE.img3
        "$dir/xpwntool" LLB.${device_model}ap.RELEASE.img3 llb.dec -iv $iv -k $key
        $bspatch llb.dec $saved_path/LLB $bpatch/LLB.${device_model}ap.RELEASE.patch
    fi
    if [[ ! -s $saved_path/RootFS.dmg ]]; then
        log "RootFS"
        name=$(echo $device_fw_key_base | $jq -j '.keys[] | select(.image == "RootFS") | .filename')
        key=$(echo $device_fw_key_base | $jq -j '.keys[] | select(.image == "RootFS") | .key')
        file_extract_from_archive "$ipsw_base_path.ipsw" $name
        "$dir/dmg" extract $name rootfs.dec -k $key
        rm $name
        "$dir/dmg" build rootfs.dec $saved_path/RootFS.dmg
    fi
    echo "device_base_vers=$device_base_vers" > ../saved/$device_type/fourthree_$device_ecid
    echo "device_base_build=$device_base_build" >> ../saved/$device_type/fourthree_$device_ecid
}

device_fourthree_step2() {
    if [[ $device_mode != "Normal" ]]; then
        error "Device is not in normal mode. Place the device in normal mode to proceed." \
              "* The device must also be restored already with Step 1: Restore."
    fi
    print "* Make sure that the device is already restored with Step 1: Restore before proceeding."
    pause
    device_iproxy
    device_sshpass alpine
    device_fourthree_check 2
    if [[ $? == 2 ]]; then
        warn "Step 2 has already been completed. Cannot continue."
        return
    fi
    print "* How much GB do you want to allocate/leave to the 6.1.3 data partition?"
    print "* The rest of the space will be allocated to the 4.3.x system."
    print "* If unsure, set it to 3 (this means 3 GB for 6.1.3, the rest for 4.3.x)."
    local size
    until [[ -n $size ]] && [ "$size" -eq "$size" ]; do
        read -p "$(input 'iOS 6.1.3 Data Partition Size (in GB): ')" size
    done
    log "iOS 6.1.3 Data Partition Size: $size GB"
    size=$((size*1024*1024*1024))
    log "Sending package files"
    $scp -P $ssh_port $jelbrek/dualbootstuff.tar root@127.0.0.1:/tmp
    log "Installing packages"
    $ssh -p $ssh_port root@127.0.0.1 "tar -xvf /tmp/dualbootstuff.tar -C /; dpkg -i /tmp/dualbootstuff/*.deb"
    log "Running TwistedMind2"
    $ssh -p $ssh_port root@127.0.0.1 "rm /TwistedMind2*; TwistedMind2 -d1 $size -s2 879124480 -d2 max"
    local tm2="$($ssh -p $ssh_port root@127.0.0.1 "ls /TwistedMind2*")"
    $scp -P $ssh_port root@127.0.0.1:$tm2 TwistedMind2
    kill $iproxy_pid
    log "Rebooting to SSH ramdisk for the next procedure"
    device_ramdisk TwistedMind2
    log "Done, proceed to Step 3 after the device boots"
}

device_fourthree_step3() {
    if [[ $device_mode != "Normal" ]]; then
        error "Device is not in normal mode. Place the device in normal mode to proceed." \
              "* The device must also be set up already with Step 2: Partition."
    fi
    print "* Make sure that the device is set up with Step 2: Partition before proceeding."
    pause
    source ../saved/$device_type/fourthree_$device_ecid
    log "4.3.x version: $device_base_vers-$device_base_build"
    local saved_path="../saved/$device_type/$device_base_build"
    device_iproxy
    device_sshpass alpine
    device_fourthree_check 3
    if [[ $? == 0 ]]; then
        warn "Step 3 has already been completed. Cannot continue."
        return
    fi
    log "Creating filesystems"
    $ssh -p $ssh_port root@127.0.0.1 "mkdir -p /mnt1 /mnt2"
    $ssh -p $ssh_port root@127.0.0.1 "/sbin/newfs_hfs -s -v System -J -b 8192 -n a=8192,c=8192,e=8192 /dev/disk0s3"
    $ssh -p $ssh_port root@127.0.0.1 "/sbin/newfs_hfs -s -v Data -J -b 8192 -n a=8192,c=8192,e=8192 /dev/disk0s4"
    log "Sending root filesystem, this will take a while."
    $scp -P $ssh_port $saved_path/RootFS.dmg root@127.0.0.1:/var
    log "Restoring root filesystem"
    $ssh -p $ssh_port root@127.0.0.1 "echo 'y' | asr restore --source /var/RootFS.dmg --target /dev/disk0s3 --erase"
    log "Checking root filesystem"
    $ssh -p $ssh_port root@127.0.0.1 "rm /var/RootFS.dmg; fsck_hfs -f /dev/disk0s3"
    log "Restoring data partition"
    $ssh -p $ssh_port root@127.0.0.1 "mount_hfs /dev/disk0s3 /mnt1; mount_hfs /dev/disk0s4 /mnt2; mv /mnt1/private/var/* /mnt2"
    log "Fixing fstab"
    $ssh -p $ssh_port root@127.0.0.1 "echo '/dev/disk0s3 / hfs rw 0 1' | tee /mnt1/private/etc/fstab; echo '/dev/disk0s4 /private/var hfs rw 0 2' | tee -a /mnt1/private/etc/fstab"
    if [[ $device_type != "iPad2,1" ]]; then
        log "Getting lockdownd"
        $scp -P $ssh_port root@127.0.0.1:/mnt1/usr/libexec/lockdownd .
        local patch="../resources/firmware/FirmwareBundles/Down_iPhone2,1_${device_base_vers}_${device_base_build}.bundle/lockdownd.patch"
        log "Patching lockdownd"
        $bspatch lockdownd lockdownd.patched "$patch"
        log "Renaming original lockdownd"
        $ssh -p $ssh_port root@127.0.0.1 "mv /mnt1/usr/libexec/lockdownd /mnt1/usr/libexec/lockdownd.orig"
        log "Copying patched lockdownd to device"
        $scp -P $ssh_port lockdownd.patched root@127.0.0.1:/mnt1/usr/libexec/lockdownd
        $ssh -p $ssh_port root@127.0.0.1 "chmod +x /mnt1/usr/libexec/lockdownd"
    fi
    log "Fixing system keybag"
    $ssh -p $ssh_port root@127.0.0.1 "mkdir -p /mnt2/keybags; ttbthingy; fixkeybag -v2; cp /tmp/systembag.kb /mnt2/keybags"
    log "Remounting data partition"
    $ssh -p $ssh_port root@127.0.0.1 "umount /mnt2; mount_hfs /dev/disk0s4 /mnt1/private/var"
    # idk if copying activation records actually works, probably not
    log "Copying activation records"
    local dmp="private/var/root/Library/Lockdown"
    $ssh -p $ssh_port root@127.0.0.1 "mkdir -p /mnt1/$dmp; cp -Rv /$dmp/* /mnt1/$dmp"
    log "Installing jailbreak"
    cp $jelbrek/freeze.tar.gz .
    gzip -d freeze.tar.gz
    cat freeze.tar | $ssh -p $ssh_port root@127.0.0.1 "tar -xvf - -C /mnt1"
    if [[ $ipsw_openssh == 1 ]]; then
        log "Installing OpenSSH"
        cat $jelbrek/sshdeb.tar | $ssh -p $ssh_port root@127.0.0.1 "tar -xvf - -C /mnt1"
        cp $jelbrek/openssh.tar.gz $jelbrek/openssl.tar.gz .
        gzip -d openssh.tar.gz
        gzip -d openssl.tar.gz
        cat openssh.tar | $ssh -p $ssh_port root@127.0.0.1 "tar -xf - -C /mnt1"
        cat openssl.tar | $ssh -p $ssh_port root@127.0.0.1 "tar -xf - -C /mnt1"
    fi
    log "Unmounting filesystems"
    $ssh -p $ssh_port root@127.0.0.1 "umount /mnt1/private/var; umount /mnt1"
    log "Sending Kernelcache and LLB"
    $scp -P $ssh_port $saved_path/Kernelcache root@127.0.0.1:/System/Library/Caches/com.apple.kernelcaches/kernelcachb
    $scp -P $ssh_port $saved_path/LLB root@127.0.0.1:/LLB
    device_fourthree_app install
    log "Done!"
}

device_fourthree_app() {
    if [[ $1 != "install" ]]; then
        device_iproxy
        print "* The default root password is: alpine"
        device_sshpass
    fi
    device_fourthree_check
    log "Installing FourThree app"
    $scp -P $ssh_port $jelbrek/fourthree.tar root@127.0.0.1:/tmp
    $ssh -p $ssh_port root@127.0.0.1 "tar -h -xvf /tmp/fourthree.tar -C /; cd /Applications/FourThree.app; chmod 6755 boot.sh FourThree kloader_ios5 /usr/bin/runasroot"
    device_uicache $1
}

device_fourthree_boot() {
    device_iproxy
    print "* The default root password is: alpine"
    device_sshpass
    device_fourthree_check
    log "Running FourThree Boot"
    $ssh -p $ssh_port root@127.0.0.1 "/Applications/FourThree.app/FourThree"
}

device_fourthree_check() {
    local opt=$1
    local check
    log "Checking if Step 1 is complete"
    check="$($ssh -p $ssh_port root@127.0.0.1 "ls /dev/disk0s2s1")"
    if [[ $check != "/dev/disk0s2s1" ]]; then
        error "Cannot find /dev/disk0s2s1. Something went wrong with Step 1" \
              "* Redo the FourThree process from Step 1"
    fi
    if [[ $opt == 1 ]]; then
        return 1
    fi
    log "Checking if Step 2 is complete"
    check="$($ssh -p $ssh_port root@127.0.0.1 "ls /dev/disk0s3 2>/dev/null")"
    if [[ $check != "/dev/disk0s3" ]]; then
        if [[ $opt == 2 ]]; then
            log "Step 2 is not complete. Proceeding"
            return 1
        fi
        error "Cannot find /dev/disk0s3. Something went wrong with Step 2" \
              "* Redo the FourThree process from Step 2"
    fi
    if [[ $opt == 2 ]]; then
        return 2
    fi
    log "Checking if Step 3 is complete"
    local kcb="/System/Library/Caches/com.apple.kernelcaches/kernelcachb"
    local kc="$($ssh -p $ssh_port root@127.0.0.1 "ls $kcb 2>/dev/null")"
    local llb="$($ssh -p $ssh_port root@127.0.0.1 "ls /LLB 2>/dev/null")"
    if [[ $kc != "$kcb" || $llb != "/LLB" ]]; then
        if [[ $opt == 3 ]]; then
            log "Step 3 is not complete. Proceeding"
            return 2
        fi
        error "Cannot find Kernelcache/LLB. Something went wrong with Step 3" \
              "* Redo the FourThree process from Step 3"
    fi
    return 0
}

menu_fourthree() {
    local menu_items
    local selected
    local back

    ipa_path=
    ipsw_fourthree=
    while [[ -z "$mode" && -z "$back" ]]; do
        menu_items=("Step 1: Restore" "Step 2: Partition" "Step 3: OS Install")
        if [[ $device_mode == "Normal" ]]; then
            menu_items+=("Reinstall App" "Boot iOS 4.3.x")
        fi
        menu_items+=("Go Back")
        menu_print_info
        print "* FourThree Utility: Dualboot iPad 2 to iOS 4.3.x"
        print "* This is a 3 step process for the device. Follow through the steps to successfully set up a dualboot."
        print "* Please read the README here: https://github.com/LukeZGD/FourThree-iPad2"
        warn "Support for FourThree Utility is no longer provided. Any issues will not be entertained nor fixed."
        echo
        print " > Main Menu > FourThree Utility"
        input "Select an option:"
        select_option "${menu_items[@]}"
        selected="${menu_items[$?]}"
        case $selected in
            "Step 1: Restore" ) ipsw_fourthree=1; menu_ipsw "iOS 6.1.3" "fourthree";;
            "Step 2: Partition" ) mode="device_fourthree_step2";;
            "Step 3: OS Install" ) mode="device_fourthree_step3";;
            "Reinstall App" ) mode="device_fourthree_app";;
            "Boot iOS 4.3.x" ) mode="device_fourthree_boot";;
            "Go Back" ) back=1;;
        esac
    done
}
