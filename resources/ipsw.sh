#!/bin/bash

IPSW32() {
    local JBFiles
    local JBMemory
    local JBSHA1
    local JBS
    
    if [[ $IPSWRestore == $IPSWCustom ]]; then
        Log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi
    
    if [[ $OSVer == 8.4.1 ]]; then
        JBFiles=(fstab.tar etasonJB-untether.tar Cydia8.tar)
        JBSHA1=6459dbcbfe871056e6244d23b33c9b99aaeca970
        JBS=2305
    else
        JBFiles=(fstab_rw.tar p0sixspwn.tar Cydia6.tar)
        JBSHA1=1d5a351016d2546aa9558bc86ce39186054dc281
        JBS=1260
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
    if [[ ! -e $IPSWCustom.ipsw ]]; then
        Echo "* By default, memory option is set to Y, you may select N later if you encounter problems"
        Echo "* If it doesn't work with both, you might not have enough RAM and/or tmp storage"
        read -p "$(Input 'Memory option? (press Enter/Return if unsure) (Y/n):')" JBMemory
        [[ $JBMemory != 'N' && $JBMemory != 'n' ]] && JBMemory="-memory" || JBMemory=
        Log "Preparing custom IPSW..."
        cd resources
        ln -sf firmware/FirmwareBundles FirmwareBundles
        $ipsw ../$IPSW.ipsw ../$IPSWCustom.ipsw $JBMemory -bbupdate -s $JBS ${JBFiles[@]}
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
        mv $iBSSb.im4p $iBECb.im4p $IPSW/Firmware/dfu
    fi
    mv $iBSS.im4p $iBEC.im4p $IPSW/Firmware/dfu
    cd $IPSW
    zip ../$IPSWCustom.ipsw -rq0 *
    cd ..
    mv $IPSW $IPSWCustom
    [[ ! -e $IPSWCustom.ipsw ]] && Error "Failed to find custom IPSW. Please run the script again"
    Log "Setting restore IPSW to: $IPSWCustom.ipsw"
    IPSWRestore=$IPSWCustom
}
