# create custom IPSW for 10.3.3

IPSW32() {
    # uses ipsw tool from OdysseusOTA/2 to create custom IPSW with jailbreak
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
        [[ $JBMemory != n ]] && [[ $JBMemory != N ]] && JBMemory="-memory" || JBMemory=
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
    IPSWRestore=$IPSWCustom
}

IPSW64() {
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
        IPSWRestore=$IPSWCustom
    else
        cp $IPSW/Firmware/dfu/$iBSS.im4p $IPSW/Firmware/dfu/$iBEC.im4p .
        [[ $ProductType == iPad4* ]] && cp $IPSW/Firmware/dfu/$iBSSb.im4p $IPSW/Firmware/dfu/$iBECb.im4p .
        cp $IPSW/Firmware/all_flash/$SEP .
    fi
    [ ! -e $IPSW.ipsw ] && Error "Failed to create custom IPSW. Please run the script again"
    if [[ $ProductType == iPad4,4 ]] || [[ $ProductType == iPad4,5 ]]; then
        iBEC=$iBECb
        iBSS=$iBSSb
    fi
    Log "Entering pwnREC mode..."
    $irecovery -f $iBSS.im4p
    $irecovery -f $iBEC.im4p
    sleep 5
    [[ $($irecovery -q 2>/dev/null | grep 'MODE' | cut -c 7-) == "Recovery" ]] && RecoveryDevice=1
    if [[ $RecoveryDevice != 1 ]]; then
        echo -e "\n$(Log 'Failed to detect device in pwnREC mode.')"
        Echo "* If your device has backlight turned on, you may try unplugging and re-plugging in your device, and attempt to continue"
        Echo "* If not, you may have to hard-reset your device and attempt to start over entering pwnDFU mode again"
        Input "Press Enter/Return to continue anyway (or press Ctrl+C to cancel)"
        read -s
    else
        Log "Found device in pwnREC mode."
    fi
    SaveOTABlobs
}
