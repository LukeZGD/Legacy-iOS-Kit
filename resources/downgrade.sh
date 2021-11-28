#!/bin/bash

FRBaseband() {
    local BasebandSHA1L
    
    if [[ $DeviceProc == 7 ]]; then
        mkdir -p saved/baseband 2>/dev/null
        cp -f $IPSWRestore/Firmware/$Baseband saved/baseband
    fi

    if [[ ! -e saved/baseband/$Baseband ]]; then
        Log "Downloading baseband..."
        $partialzip $BasebandURL Firmware/$Baseband $Baseband
        $partialzip $BasebandURL BuildManifest.plist BuildManifest.plist
        mkdir -p saved/$ProductType saved/baseband 2>/dev/null
        mv $Baseband saved/baseband
        mv BuildManifest.plist saved/$ProductType
        BuildManifest="saved/$ProductType/BuildManifest.plist"
    elif [[ $DeviceProc != 7 ]]; then
        BuildManifest="saved/$ProductType/BuildManifest.plist"
    fi

    BasebandSHA1L=$(shasum saved/baseband/$Baseband | awk '{print $1}')
    if [[ ! -e $(ls saved/baseband/$Baseband) || $BasebandSHA1L != $BasebandSHA1 ]]; then
        rm -f saved/baseband/$Baseband saved/$ProductType/BuildManifest.plist
        if [[ $DeviceProc == 7 ]]; then
            Error "Downloading/verifying baseband failed. Please run the script again"
        else
            Log "Downloading/verifying baseband failed, will proceed with --latest-baseband flag"
            return 1
        fi
    fi
}

Downgrade() {
    local ExtraArgs=("--use-pwndfu")
    local IPSWExtract
    local IPSWSHA1
    local IPSWSHA1L
    local Jailbreak
    local Verify=1
    
    Log "Select your options when asked. If unsure, go for the defaults (press Enter/Return)."
    echo

    if [[ $OSVer == "Other" ]]; then
        Input "Select your IPSW file in the file selection window."
        IPSW="$($zenity --file-selection --file-filter='IPSW | *.ipsw' --title="Select IPSW file")"
        [[ ! -s "$IPSW" ]] && Error "No IPSW selected, or IPSW file not found."
        IPSW="${IPSW%?????}"
        Log "Selected IPSW file: $IPSW.ipsw"
        Input "Select your SHSH file in the file selection window."
        SHSH="$($zenity --file-selection --file-filter='SHSH | *.shsh *.shsh2' --title="Select SHSH file")"
        [[ ! -s "$SHSH" ]] && Error "No SHSH selected, or SHSH file not found."
        Log "Selected SHSH file: $SHSH"

        unzip -o -j "$IPSW.ipsw" Restore.plist -d tmp
        BuildVer=$(cat tmp/Restore.plist | grep -i ProductBuildVersion -A 1 | grep -oPm1 "(?<=<string>)[^<]+")
        Log "Getting firmware keys for $ProductType-$BuildVer"
        mkdir resources/firmware/$ProductType/$BuildVer 2>/dev/null
        curl -L https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/raw/master/$ProductType/$BuildVer/index.html -o tmp/index.html
        mv tmp/index.html resources/firmware/$ProductType/$BuildVer

    elif [[ $DeviceProc != 7 ]]; then
        Input "Jailbreak Option"
        Echo "* When this option is enabled, your device will be jailbroken on restore."
        if [[ $ProductType == "iPad2,5" || $ProductType == "iPad2,6" || $ProductType == "iPad2,7" ]]; then
            Echo "* Based on some reported issues, Jailbreak Option might be broken for iPad mini 1 devices."
            Echo "* I recommend to disable the option for these devices and sideload EtasonJB, HomeDepot, or daibutsu manually."
        fi
        Echo "* This option is enabled by default (Y)."
        read -p "$(Input 'Enable this option? (Y/n):')" Jailbreak
        
        if [[ $Jailbreak != 'N' && $Jailbreak != 'n' ]]; then
            JailbreakSet
            Log "Jailbreak option enabled. Using $JBName for the jailbreak"
        else
            Log "Jailbreak option disabled by user."
        fi
        echo
    fi
    
    if [[ $OSVer != "Other" ]]; then
        IPSW="${IPSWType}_${OSVer}_${BuildVer}_Restore"
        IPSWCustom="${IPSWType}_${OSVer}_${BuildVer}_Custom"

        if [[ $Jailbreak == 1 ]]; then
            [[ -e "$IPSWCustom.ipsw" ]] && Verify=
        fi

        MemoryOption

        SaveOTABlobs

        if [[ ! -e "$IPSW.ipsw" && $Verify == 1 ]]; then
            Log "iOS $OSVer IPSW for $ProductType cannot be found."
            Echo "* If you already downloaded the IPSW, move/copy it to the directory where the script is located."
            Echo "* Do NOT rename the IPSW as the script will fail to detect it."
            Echo "* The script will now proceed to download it for you. If you want to download it yourself, here is the link: $(cat $Firmware/$BuildVer/url)"
            Log "Downloading IPSW... (Press Ctrl+C to cancel)"
            curl -L $(cat $Firmware/$BuildVer/url) -o tmp/$IPSW.ipsw
            mv tmp/$IPSW.ipsw .
        fi

        if [[ $Verify == 1 ]]; then
            Log "Verifying IPSW..."
            IPSWSHA1=$(cat $Firmware/$BuildVer/sha1sum)
            Log "Expected SHA1sum: $IPSWSHA1"
            IPSWSHA1L=$(shasum $IPSW.ipsw | awk '{print $1}')
            Log "Actual SHA1sum:   $IPSWSHA1L"
            if [[ $IPSWSHA1L != $IPSWSHA1 ]]; then
                Error "Verifying IPSW failed. Your IPSW may be corrupted or incomplete. Delete/replace the IPSW and run the script again" \
                "SHA1sum mismatch. Expected $IPSWSHA1, got $IPSWSHA1L"
            fi
            Log "IPSW SHA1sum matches."
        elif [[ -e "$IPSWCustom.ipsw" ]]; then
            Log "Found existing Custom IPSW. Skipping IPSW verification."
            Log "Setting restore IPSW to: $IPSWCustom.ipsw"
            IPSWRestore=$IPSWCustom
        fi
    
        if [[ $DeviceState == "Normal" && $iBSSBuildVer == $BuildVer && -e "$IPSW.ipsw" ]]; then
            Log "Extracting iBSS from IPSW..."
            mkdir -p saved/$ProductType 2>/dev/null
            unzip -o -j $IPSW.ipsw Firmware/dfu/$iBSS.dfu -d saved/$ProductType
        fi
    else
        IPSWCustom=0
    fi

    [[ $DeviceState == "Normal" ]] && kDFU

    if [[ $Jailbreak == 1 ]]; then
        IPSW32
        IPSWExtract="$IPSWCustom"
    else
        IPSWExtract="$IPSW"
    fi

    Log "Extracting IPSW: $IPSWExtract.ipsw"
    unzip -oq "$IPSWExtract.ipsw" -d "$IPSWExtract"/

    if [[ ! $IPSWRestore ]]; then
        Log "Setting restore IPSW to: $IPSW.ipsw"
        IPSWRestore="$IPSW"
    fi

    Log "Proceeding to futurerestore..."
    [[ $platform == "linux" ]] && Echo "* Enter root password of your PC when prompted"
    cd resources
    $SimpleHTTPServer &
    ServerPID=$!
    cd ..

    if [[ $DeviceProc == 7 ]]; then
        # Send dummy file for device detection
        $irecovery -f README.md
        sleep 2
        ExtraArgs+=("-s" "$IPSWRestore/Firmware/all_flash/$SEP" "-m" "$BuildManifest")
    else
        ExtraArgs+=("--no-ibss")
    fi

    if [[ $Baseband == 0 ]]; then
        Log "Device $ProductType has no baseband"
        ExtraArgs+=("--no-baseband")
    else
        FRBaseband
        if [[ $? == 1 ]]; then
            ExtraArgs+=("--latest-baseband")
        else
            ExtraArgs+=("-b" "saved/baseband/$Baseband" "-p" "$BuildManifest")
        fi
    fi
    $futurerestore -t "$SHSH" "${ExtraArgs[@]}" "$IPSWRestore.ipsw"

    echo
    Log "Restoring done!"
    Log "Downgrade script done!"
}
