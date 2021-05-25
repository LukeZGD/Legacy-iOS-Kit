#!/bin/bash
local Baseband5

Downgrade() {
    local IPSWSHA1
    local IPSWSHA1L
    local Jailbreak
    
    if [[ $OSVer == "Other" ]]; then
        Echo "* Move/copy the IPSW and SHSH to the directory where the script is located"
        Echo "* Remember to create a backup of the SHSH"
        read -p "$(Input 'Path to IPSW (drag IPSW to terminal window):')" IPSW
        IPSW="$(basename $IPSW .ipsw)"
        read -p "$(Input 'Path to SHSH (drag SHSH to terminal window):')" SHSH
    
    elif [[ $Mode == "Downgrade" && $DeviceProc != 7 ]]; then
        read -p "$(Input 'Jailbreak the selected iOS version? (y/N):')" Jailbreak
        [[ ${Jailbreak^} == 'Y' ]] && Jailbreak=1
    fi
    
    if [[ $Mode == "Downgrade" && $ProductType == iPhone5,1 && $Jailbreak != 1 ]]; then
        Echo "* By default, iOS-OTA-Downgrader now flashes the iOS 8.4.1 baseband to iPhone5,1"
        Echo "* Flashing the latest baseband is still available as an option but beware of problems it may cause"
        Echo "* There are potential network issues that with the latest baseband when used on iOS 8.4.1"
        read -p "$(Input 'Flash the latest baseband? (y/N) (press Enter/Return if unsure):')" Baseband5
        if [[ ${Baseband5^} == 'Y' ]]; then
            Baseband5=0
        else
            BasebandURL=$(cat $Firmware/12H321/url)
            Baseband="Mav5-8.02.00.Release.bbfw"
            BasebandSHA1="db71823841ffab5bb41341576e7adaaeceddef1c"
        fi
    fi
    
    if [[ $OSVer != "Other" ]]; then
        [[ $DeviceProc != 7 ]] && SaveOTABlobs
    
        IPSW="${IPSWType}_${OSVer}_${BuildVer}_Restore"
        IPSWCustom="${IPSWType}_${OSVer}_${BuildVer}_Custom"
    
        if [[ ! -e "$IPSW.ipsw" && ! -e "$IPSWCustom.ipsw" ]]; then
            Log "iOS $OSVer IPSW cannot be found."
            Echo "* If you already downloaded the IPSW, did you put it in the same directory as the script?"
            Echo "* Do NOT rename the IPSW as the script will fail to detect it"
            Log "Downloading IPSW... (Press Ctrl+C to cancel)"
            curl -L $(cat $Firmware/$BuildVer/url) -o tmp/$IPSW.ipsw
            mv tmp/$IPSW.ipsw .
        fi
    
        if [[ $Jailbreak != 1 && ! -e "$IPSWCustom.ipsw" ]]; then
            Log "Verifying IPSW..."
            IPSWSHA1=$(cat $Firmware/$BuildVer/sha1sum)
            IPSWSHA1L=$(shasum $IPSW.ipsw | awk '{print $1}')
            if [[ $IPSWSHA1L != $IPSWSHA1 ]]; then
                Error "Verifying IPSW failed. Your IPSW may be corrupted or incomplete." \
                "Delete/replace the IPSW and run the script again"
            fi
        else
            Log "Detected existing Custom IPSW. Skipping verification."
            Log "Setting restore IPSW to: $IPSWCustom.ipsw"
            IPSWRestore=$IPSWCustom
        fi
    
        if [[ $DeviceState == "Normal" && $iBSSBuildVer == $BuildVer ]]; then
            Log "Extracting iBSS from IPSW..."
            mkdir -p saved/$ProductType 2>/dev/null
            unzip -o -j $IPSW.ipsw Firmware/dfu/$iBSS.dfu -d saved/$ProductType
        fi
    fi
    
    [[ $DeviceState == "Normal" ]] && kDFU
    [[ $Jailbreak == 1 ]] && IPSW32
    
    Log "Extracting IPSW..."
    unzip -q $IPSW.ipsw -d $IPSW/
    
    if [[ $DeviceProc == 7 ]]; then
        IPSW64
        pwnREC
        SaveOTABlobs
    elif [[ $Jailbreak != 1 && $OSVer != "Other" ]]; then
        Log "Preparing for futurerestore... (Enter root password of your PC/Mac when prompted)"
        cd resources
        sudo bash -c "$python -m SimpleHTTPServer 80 &"
        cd ..
    fi
    
    if [[ ! $IPSWRestore ]]; then
        Log "Setting restore IPSW to: $IPSW.ipsw"
        IPSWRestore="$IPSW"
    fi
    
    if [[ $Jailbreak == 1 ]]; then
        iDeviceRestore
    else
        FutureRestore
    fi
    
    echo
    Log "Restoring done!"
    if [[ $Jailbreak != 1 && $DeviceProc != 7 && $OSVer != "Other" ]]; then
        Log "Stopping local server... (Enter root password of your PC/Mac when prompted)"
        ps aux | awk '/python/ {print "sudo kill -9 "$2" 2>/dev/null"}' | bash
    fi
    Log "Downgrade script done!"
}

iDeviceRestore() {
    Log "Proceeding to idevicerestore... (Enter root password of your PC/Mac when prompted)"
    [[ $platform == "macos" ]] && sudo codesign --sign - --force --deep $idevicerestore
    mkdir shsh
    mv $SHSH shsh/${UniqueChipID}-${ProductType}-${OSVer}.shsh
    $idevicerestore -ewy $IPSWRestore.ipsw
    if [[ $platform == "macos" && $? != 0 ]]; then
        Log "An error seems to have occurred when running idevicerestore."
        Echo "* If this is the 'Killed: 9' error or similar, try these steps:"
        Echo "* cd to where the script is located, then run"
        Echo "* sudo codesign --sign - --force --deep resources/tools/idevicerestore_macos"
    fi
}

FutureRestore() {
    local BasebandSHA1L
    local ExtraArgs
    local futurerestore
    
    if [[ $DeviceProc == 7 ]]; then
        ExtraArgs="-s $SEP -m $BuildManifest"
        futurerestore=$futurerestore2
    else
        BuildManifest="BuildManifest.plist"
        ExtraArgs="--use-pwndfu"
        futurerestore=$futurerestore1
    fi
    
    Log "Proceeding to futurerestore..."
    if [[ $Baseband == 0 ]]; then
        Log "Device $ProductType has no baseband"
        $futurerestore -t $SHSH --no-baseband $ExtraArgs $IPSWRestore.ipsw
    else
        FRBaseband
        BasebandSHA1L=$(shasum $Baseband | awk '{print $1}')
        Log "Proceeding to futurerestore..."
        if [[ ! -e *.bbfw ]] || [[ $BasebandSHA1L != $BasebandSHA1 ]]; then
            rm -f saved/$ProductType/*.bbfw saved/$ProductType/BuildManifest.plist
            Log "Downloading/verifying baseband failed."
            Echo "* Your device is still in kDFU mode and you may run the script again"
            Echo "* You can also continue and futurerestore can attempt to download the baseband again"
            Input "Press Enter/Return to continue (or press Ctrl+C to cancel)"
            read -s
            $futurerestore -t $SHSH --latest-baseband --use-pwndfu "$IPSWRestore.ipsw"
        else
            $futurerestore -t $SHSH -b $Baseband -p $BuildManifest $ExtraArgs "$IPSWRestore.ipsw"
        fi
    fi
}

FRBaseband() {
    if [[ $DeviceProc == 7 ]]; then
        cp $IPSW/Firmware/$Baseband .
    elif [[ $ProductType == "iPhone5,1" && $Baseband5 != 0 ]]; then
        unzip -o -j $IPSW.ipsw Firmware/$Baseband -d .
        cp $BuildManifest BuildManifest.plist
    elif [[ ! -e saved/baseband/$Baseband ]]; then
        Log "Downloading baseband..."
        $partialzip $BasebandURL Firmware/$Baseband $Baseband
        $partialzip $BasebandURL BuildManifest.plist BuildManifest.plist
        mkdir -p saved/$ProductType 2>/dev/null
        mkdir -p saved/baseband 2>/dev/null
        cp $Baseband saved/baseband
        cp BuildManifest.plist saved/$ProductType
    else
        cp saved/baseband/$Baseband saved/$ProductType/BuildManifest.plist .
    fi
}
