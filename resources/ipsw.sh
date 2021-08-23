#!/bin/bash

IPSW32() {
    local JBFiles
    local JBMemory
    local JBSHA1
    local JBPartSize
    local RootFS=058-24073-023.dmg
    local HWModel2="$(echo $HWModel | sed 's/.*/\u&/')"

    if [[ $IPSWRestore == $IPSWCustom ]]; then
        Log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi

    if [[ $Jailbreak == 1 && $JBDaibutsu == 1 ]]; then
        [[ ! -e daibutsu_v1.2.ipa ]] && Error "daibutsu v1.2 ipa not found. Download daibutsu ipa from the official website before proceeding."
        [[ ! -e saved/$ProductType/dyld_shared_cache_armv7 ]] && Error "dyld cache missing. Your device must be jailbroken with daibutsu and booted in normal mode before proceeding." "* Force restart your device to boot back to normal mode"
        Log "Using daibutsu jailbreak"
        JBFiles=("../tmp/Payload/daibutsu.app/cydia.tar" "../tmp/daibutsu.tar" "jailbreak/symlink.tar")
        JBPartSize="-s 2305"
        Log "Preparing files..."
        unzip -q daibutsu_v1.2.ipa -d tmp
        echo $HWModel2 > tmp/hwmodel
        mkdir tmp/root
        cd tmp/root
        mkdir -p private/etc private/var/root/media/Cydia/Autoinstall usr/libexec
        touch .cydia_no_stash .installed_daibutsu
        mv ../Payload/daibutsu.app/daibutsu .
        mv ../Payload/daibutsu.app/dirhelper usr/libexec
        mv ../Payload/daibutsu.app/fstab private/etc
        mv ../Payload/daibutsu.app/untether.deb private/var/root/media/Cydia/Autoinstall
        sudo chown -R 0:0 * .cydia_no_stash .installed_daibutsu
        sudo chmod -R 0644 * .cydia_no_stash .installed_daibutsu
        sudo chmod 0755 daibutsu usr/libexec/dirhelper usr/lib/exec/CrashHousekeeping_s
        #sudo ln -sf /daibutsu usr/libexec/CrashHousekeeping_s
        sudo tar -cvf ../daibutsu.tar * .cydia_no_stash .installed_daibutsu
        sudo rm -rf *
        mkdir -p System/Library/Caches/com.apple.dyld
        cp ../../saved/$ProductType/dyld_shared_cache_armv7 System/Library/Caches/com.apple.dyld
        sudo chown -R 0:0 *
        sudo chmod -R 0644 *
        sudo tar -cvf ../dyld.tar *
        sudo rm -rf *
        cd ../..
    elif [[ $Jailbreak == 1 ]]; then
        if [[ $OSVer == 8.4.1 ]]; then
            JBFiles=("fstab.tar" "etasonJB-untether.tar" "Cydia8.tar")
            JBSHA1="6459dbcbfe871056e6244d23b33c9b99aaeca970"
            JBPartSize="-s 2305"
        elif [[ $OSVer == 6.1.3 ]]; then
            JBFiles=("fstab_rw.tar" "p0sixspwn.tar" "Cydia6.tar")
            JBSHA1="1d5a351016d2546aa9558bc86ce39186054dc281"
            JBPartSize="-s 1260"
        else
            Error "No OSVer selected?"
        fi
        if [[ ! -e resources/jailbreak/${JBFiles[2]} ]]; then
            cd tmp
            Log "Downloading jailbreak files..."
            SaveFile https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/jailbreak/${JBFiles[2]} ${JBFiles[2]} $JBSHA1
            mv ${JBFiles[2]} ../resources/jailbreak
            cd ..
        fi
        for i in {0..2}; do
            JBFiles[$i]=jailbreak/${JBFiles[$i]}
        done
    fi

    if [[ ! -e $IPSWCustom.ipsw ]]; then
        Echo "* By default, memory option is set to Y, you may select N later if you encounter problems"
        Echo "* If it doesn't work with both, you might not have enough RAM and/or tmp storage"
        read -p "$(Input 'Memory option? (press Enter/Return if unsure) (Y/n):')" JBMemory
        [[ $JBMemory != 'N' && $JBMemory != 'n' ]] && JBMemory="-memory" || JBMemory=
        Log "Preparing custom IPSW..."
        cd resources
        ln -sf firmware/FirmwareBundles FirmwareBundles
        $ipsw ./../$IPSW.ipsw ./../$IPSWCustom.ipsw $JBMemory -bbupdate $JBPartSize ${JBFiles[@]}
        cd ..
    fi
: '
    if [[ $Jailbreak == 1 && $JBDaibutsu == 1 ]]; then
        unzip -o -j $IPSWCustom.ipsw $RootFS -d tmp
        $dmg extract tmp/$RootFS tmp/rootfs.dmg
        $hfsplus tmp/rootfs.dmg mv System/Library/LaunchDaemons Library/LaunchDaemons
        $hfsplus tmp/rootfs.dmg mkdir System/Library/LaunchDaemons
        $hfsplus tmp/rootfs.dmg mv Library/LaunchDaemons/bootps.plist System/Library/LaunchDaemons/bootps.plist
        $hfsplus tmp/rootfs.dmg mv Library/LaunchDaemons/com.apple.CrashHousekeeping.plist System/Library/LaunchDaemons/com.apple.CrashHousekeeping.plist
        $hfsplus tmp/rootfs.dmg mv Library/LaunchDaemons/com.apple.MobileFileIntegrity.plist System/Library/LaunchDaemons/com.apple.MobileFileIntegrity.plist
        $hfsplus tmp/rootfs.dmg mv Library/LaunchDaemons/com.apple.jetsamproperties.$HWModel2.plist System/Library/LaunchDaemons/com.apple.jetsamproperties.$HWModel2.plist
        $hfsplus tmp/rootfs.dmg mv Library/LaunchDaemons/com.apple.mDNSResponder.plist System/Library/LaunchDaemons/com.apple.mDNSResponder.plist_
        $hfsplus tmp/rootfs.dmg mv Library/LaunchDaemons/com.apple.mobile.softwareupdated.plist System/Library/LaunchDaemons/com.apple.mobile.softwareupdated.plist_
        $hfsplus tmp/rootfs.dmg mv Library/LaunchDaemons/com.apple.softwareupdateservicesd.plist System/Library/LaunchDaemons/com.apple.softwareupdateservicesd.plist_
        $hfsplus tmp/rootfs.dmg mv usr/libexec/CrashHousekeeping usr/libexec/CrashHousekeeping_o
        $hfsplus tmp/rootfs.dmg symlink usr/libexec/CrashHousekeeping daibutsu
        $hfsplus tmp/rootfs.dmg chmod 755 usr/libexec/CrashHousekeeping
        $dmg build tmp/rootfs.dmg tmp/$RootFS
        cd tmp
        zip -r0 ../$IPSWCustom.ipsw $RootFS
        cd ..
    fi
'
    if [[ ! -e $IPSWCustom.ipsw ]]; then
        Error "Failed to find custom IPSW. Please run the script again" \
        "You may try selecting N for memory option"
    fi

    Log "Setting restore IPSW to: $IPSWCustom.ipsw"
    IPSWRestore=$IPSWCustom
}

IPSW64() {
    if [[ $IPSWRestore == $IPSWCustom ]]; then
        Log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi
    
    Log "Preparing custom IPSW..."
    $bspatch $IPSW/Firmware/dfu/$iBSS.im4p $iBSS.im4p resources/patches/$iBSS.patch
    $bspatch $IPSW/Firmware/dfu/$iBEC.im4p $iBEC.im4p resources/patches/$iBEC.patch
    if [[ $ProductType == "iPad4"* ]]; then
        $bspatch $IPSW/Firmware/dfu/$iBSSb.im4p $iBSSb.im4p resources/patches/$iBSSb.patch
        $bspatch $IPSW/Firmware/dfu/$iBECb.im4p $iBECb.im4p resources/patches/$iBECb.patch
        mv -f $iBSSb.im4p $iBECb.im4p $IPSW/Firmware/dfu
    fi
    mv -f $iBSS.im4p $iBEC.im4p $IPSW/Firmware/dfu
    cd $IPSW
    zip -rq0 ../$IPSWCustom.ipsw *
    cd ..
    mv $IPSW $IPSWCustom
    if [[ ! -e $IPSWCustom.ipsw ]]; then
        Error "Failed to find custom IPSW. Please run the script again"
    fi

    Log "Setting restore IPSW to: $IPSWCustom.ipsw"
    IPSWRestore=$IPSWCustom
}
