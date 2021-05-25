#!/bin/bash

IPSW32() {
    local JBFiles
    local JBMemory
    local JBSHA1
    local JBS
    
    if [[ $IPSWRestore == $IPSWCustom ]]; then
        Log "Detected existing Custom IPSW. Skipping IPSW creation."
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
        cp ${JBFiles[2]} ../resources/jailbreak
        cd ..
    fi
    for i in {0..2}; do
        JBFiles[$i]=jailbreak/${JBFiles[$i]}
    done
    if [[ ! -e $IPSWCustom.ipsw ]]; then
        Echo "* By default, memory option is set to Y, you may select N later if you encounter problems"
        Echo "* If it doesn't work with both, you might not have enough RAM and/or tmp storage"
        read -p "$(Input 'Memory option? (press Enter/Return if unsure) (Y/n):')" JBMemory
        [[ ${JBMemory^} != 'N' ]] && JBMemory="-memory" || JBMemory=
        Log "Preparing custom IPSW..."
        cd resources
        ln -sf firmware/FirmwareBundles FirmwareBundles
        $ipsw ../$IPSW.ipsw ../$IPSWCustom.ipsw $JBMemory -bbupdate -s $JBS ${JBFiles[@]}
        cd ..
    fi
    if [[ ! -e $IPSWCustom.ipsw ]]; then
        Error "Failed to find custom IPSW. Please run the script again" \
        "You may try selecting N for memoryoption"
    fi
    Log "Setting restore IPSW to: $IPSWCustom.ipsw"
    IPSWRestore=$IPSWCustom
}

IPSW64() {
    if [[ $IPSWRestore == $IPSWCustom ]]; then
        Log "Detected existing Custom IPSW. Skipping IPSW creation."
        return
    fi
    
    if [ ! -e $IPSWCustom.ipsw ]; then
        Log "Preparing custom IPSW..."
        cp $IPSW/Firmware/all_flash/$SEP .
        $bspatch $IPSW/Firmware/dfu/$iBSS.im4p $iBSS.im4p resources/patches/$iBSS.patch
        $bspatch $IPSW/Firmware/dfu/$iBEC.im4p $iBEC.im4p resources/patches/$iBEC.patch
        if [[ $ProductType == iPad4* ]]; then
            $bspatch $IPSW/Firmware/dfu/$iBSSb.im4p $iBSSb.im4p resources/patches/$iBSSb.patch
            $bspatch $IPSW/Firmware/dfu/$iBECb.im4p $iBECb.im4p resources/patches/$iBECb.patch
            cp -f $iBSSb.im4p $iBECb.im4p $IPSW/Firmware/dfu
        fi
        cp -f $iBSS.im4p $iBEC.im4p $IPSW/Firmware/dfu
        cd $IPSW
        zip ../$IPSWCustom.ipsw -rq0 *
        cd ..
        mv $IPSW $IPSWCustom
        Log "Setting restore IPSW to: $IPSWCustom.ipsw"
        IPSWRestore=$IPSWCustom
    else
        cp $IPSW/Firmware/dfu/$iBSS.im4p $IPSW/Firmware/dfu/$iBEC.im4p .
        [[ $ProductType == "iPad4"* ]] && cp $IPSW/Firmware/dfu/$iBSSb.im4p $IPSW/Firmware/dfu/$iBECb.im4p .
        cp $IPSW/Firmware/all_flash/$SEP .
    fi
    [[ ! -e $IPSW.ipsw ]] && Error "Failed to find custom IPSW. Please run the script again"
    if [[ $ProductType == "iPad4,4" || $ProductType == "iPad4,5" ]]; then
        Log "iPad mini 2 device detected. Setting iBSS and iBEC to 'ipad4b'"
        iBEC=$iBECb
        iBSS=$iBSSb
    fi
}
