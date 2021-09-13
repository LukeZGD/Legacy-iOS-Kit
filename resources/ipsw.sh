#!/bin/bash

IPSW32() {
    local Bundle="resources/firmware/FirmwareBundles/Down_${ProductType}_${OSVer}_${BuildVer}.bundle"
    local ExtraArgs
    local JBFiles
    local JBSHA1

    if [[ $IPSWRestore == $IPSWCustom ]]; then
        Log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi

    if [[ -e $Bundle/Info.plist.bak ]]; then
        rm $Bundle/Info.plist
        mv $Bundle/Info.plist.bak $Bundle/Info.plist
    fi

    if [[ $JBDaibutsu == 1 ]]; then
        ExtraArgs+="-daibutsu "
        SaveExternal dora2-iOS daibutsuCFW
        echo '#!/bin/bash' > tmp/reboot.sh
        echo "mount_hfs /dev/disk0s1s1 /mnt1; mount_hfs /dev/disk0s1s2 /mnt2" >> tmp/reboot.sh
        echo "nvram -d boot-partition; nvram -d boot-ramdisk" >> tmp/reboot.sh
        echo "/usr/bin/haxx_overwrite -$HWModel" >> tmp/reboot.sh

    elif [[ $Jailbreak == 1 ]]; then
        cp $Bundle/Info.plist $Bundle/Info.plist.bak
        sed -z -i "s|</dict>\n</plist>|\t<key>needPref</key>\n\t<true/>\n</dict>\n</plist>|g" $Bundle/Info.plist
        if [[ $OSVer == "8.4.1" ]]; then
            JBFiles=("fstab.tar" "etasonJB-untether.tar" "Cydia8.tar")
            JBSHA1="6459dbcbfe871056e6244d23b33c9b99aaeca970"
            ExtraArgs+="-s 2305 "
        elif [[ $OSVer == "6.1.3" ]]; then
            JBFiles=("fstab_rw.tar" "p0sixspwn.tar" "Cydia6.tar")
            JBSHA1="1d5a351016d2546aa9558bc86ce39186054dc281"
            ExtraArgs+="-s 1260 "
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
    ExtraArgs+="-bbupdate"

    if [[ ! -e $IPSWCustom.ipsw ]]; then
        Echo "* By default, memory option is set to Y, you may select N later if you encounter problems"
        Echo "* If it doesn't work with both, you might not have enough RAM and/or tmp storage"
        read -p "$(Input 'Memory option? (press Enter/Return if unsure) (Y/n):')" JBMemory
        [[ $JBMemory != 'N' && $JBMemory != 'n' ]] && ExtraArgs+=" -memory"
        Log "Preparing custom IPSW..."
        cd resources
        rm -rf FirmwareBundles
        if [[ $JBDaibutsu == 1 ]]; then
            ln -sf firmware/JailbreakBundles FirmwareBundles
        else
            ln -sf firmware/FirmwareBundles FirmwareBundles
        fi
        $ipsw ./../$IPSW.ipsw ./../$IPSWCustom.ipsw $ExtraArgs ${JBFiles[@]}
        cd ..
    fi
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
