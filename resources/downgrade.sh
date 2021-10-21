#!/bin/bash

iDeviceRestore() {
    Log "Proceeding to idevicerestore... (Enter root password of your PC/Mac when prompted)"
    [[ $platform == "macos" ]] && sudo codesign --sign - --force --deep $idevicerestore
    mkdir shsh
    mv $SHSH shsh/${UniqueChipID}-${ProductType}-${OSVer}.shsh
    $idevicerestore -ewy $IPSWRestore.ipsw
    if [[ $? != 0 && $platform != "linux" ]]; then
        Log "An error seems to have occurred when running idevicerestore."
        if [[ $platform == "macos" ]]; then
            Echo "* If this is the \"Killed: 9\" error or similar, try these steps:"
            Echo "* Using Terminal, cd to where the script is located, then run"
            Echo "* sudo codesign --sign - --force --deep resources/tools/idevicerestore_macos"
        elif [[ $platform == "win" ]]; then
            Echo "* Windows users may encounter errors like \"Unable to send APTicket\" or \"Unable to send iBEC\" in the restore process."
            Echo "* To fix this, follow troubleshooting steps here: https://github.com/LukeZGD/iOS-OTA-Downgrader/wiki/Troubleshooting#windows"
        fi
    fi
}

FRBaseband() {
    local BasebandSHA1L
    
    if [[ $DeviceProc == 7 ]] || [[ $ProductType == "iPhone5,1" && $Baseband5 != 0 ]]; then
        mkdir -p saved/baseband 2>/dev/null
        cp -f $IPSWRestore/Firmware/$Baseband saved/baseband
    elif [[ ! -e saved/baseband/$Baseband ]]; then
        Log "Downloading baseband..."
        $partialzip $BasebandURL Firmware/$Baseband $Baseband
        $partialzip $BasebandURL BuildManifest.plist BuildManifest.plist
        mkdir -p saved/$ProductType saved/baseband 2>/dev/null
        mv $Baseband saved/baseband
        mv BuildManifest.plist saved/$ProductType
        BuildManifest="saved/$ProductType/BuildManifest.plist"
    else
        BuildManifest="saved/$ProductType/BuildManifest.plist"
    fi
    
    BasebandSHA1L=$(shasum saved/baseband/$Baseband | awk '{print $1}')
    if [[ ! -e $(ls saved/baseband/$Baseband) || $BasebandSHA1L != $BasebandSHA1 ]]; then
        rm -f saved/baseband/$Baseband saved/$ProductType/BuildManifest.plist
        Error "Downloading/verifying baseband failed. Please run the script again"
    fi
}

FutureRestore() {
    local ExtraArgs=()

    [[ $IPSWCustomW != 2 ]] && ExtraArgs=("--use-pwndfu")
    if [[ $DeviceProc == 7 ]]; then
        ExtraArgs+=("-s" "$IPSWRestore/Firmware/all_flash/$SEP" "-m" "$BuildManifest")
    else
        ExtraArgs+=("--no-ibss" "--boot-args" "rd=md0 -restore -v")
    fi

    Log "Proceeding to futurerestore..."
    if [[ $Baseband == 0 ]]; then
        Log "Device $ProductType has no baseband"
        $futurerestore -t "$SHSH" --no-baseband "${ExtraArgs[@]}" "$IPSWRestore.ipsw"
    else
        FRBaseband
        $futurerestore -t "$SHSH" -b saved/baseband/$Baseband -p $BuildManifest "${ExtraArgs[@]}" "$IPSWRestore.ipsw"
    fi
}

Downgrade() {
    local IPSWExtract
    local IPSWSHA1
    local IPSWSHA1L
    local Jailbreak
    local JBName
    local Verify
    
    Log "Select your options when asked. If unsure, go for the defaults (press Enter/Return)."
    echo

    if [[ $OSVer == "Other" ]]; then
        if [[ $platform == "linux" ]]; then
            Input "Select your IPSW file in the file selection window."
            IPSW="$(zenity --file-selection --file-filter='IPSW | *.ipsw' --title="Select IPSW file")"
            IPSW="${IPSW%?????}"
            Log "Selected IPSW file: $IPSW.ipsw"
            Input "Select your SHSH file in the file selection window."
            SHSH="$(zenity --file-selection --file-filter='SHSH | *.shsh *.shsh2' --title="Select SHSH file")"
            Log "Selected SHSH file: $SHSH"
        else
            Input "Enter the names of your IPSW and SHSH files below."
            Echo "* Move/copy the IPSW and SHSH files to the directory where the script is located"
            Echo "* When entering the names of IPSW and SHSH, enter the full name including the file extension"
            Echo "* Make sure to create a backup of the SHSH"
            read -p "$(Input 'Enter name of IPSW file:')" IPSW
            IPSW="$(basename "$IPSW" .ipsw)"
            read -p "$(Input 'Enter name of SHSH file:')" SHSH
        fi

    elif [[ $Mode == "Downgrade" && $DeviceProc != 7 ]]; then
        Input "Jailbreak Option"
        Echo "* When this option is enabled, your device will be jailbroken on restore."
        Echo "* This option is enabled by default (Y)."
        read -p "$(Input 'Enable this option? (Y/n):')" Jailbreak
        
        if [[ $Jailbreak != 'N' && $Jailbreak != 'n' ]]; then
            Jailbreak=1
            if [[ $ProductType == "iPhone4,1" || $ProductType == "iPad2,4" ||
                  $ProductType == "iPad2,5" || $ProductType == "iPad2,6" ||
                  $ProductType == "iPad2,7" || $ProductType == "iPod5,1" ]] ||
               [[ $ProductType == "iPad3"* && $DeviceProc == 5 ]]; then
                [[ $OSVer == "8.4.1" ]] && JBDaibutsu=1
            fi

            if [[ $JBDaibutsu == 1 ]]; then
                JBName="daibutsu"
            elif [[ $OSVer == "8.4.1" ]]; then
                JBName="EtasonJB"
            elif [[ $OSVer == "6.1.3" ]]; then
                JBName="p0sixspwn"
            fi

            Log "Jailbreak option enabled. Using $JBName for the jailbreak"
        fi
        echo
    fi
    
    if [[ $Mode == "Downgrade" && $ProductType == "iPhone5,1" && $Jailbreak != 1 ]]; then
        Input "Latest Baseband Option"
        Echo "* iOS-OTA-Downgrader flashes the iOS 8.4.1 baseband to iPhone5,1."
        Echo "* When this option is enabled, the latest baseband will be flashed instead, but beware of problems it may cause."
        Echo "* This option is disabled by default (N)."
        read -p "$(Input 'Enable this option? (y/N):')" Baseband5
        if [[ $Baseband5 == 'Y' || $Baseband5 == 'y' ]]; then
            Baseband5=0
        else
            BasebandURL=$(cat $Firmware/12H321/url)
            Baseband="Mav5-8.02.00.Release.bbfw"
            BasebandSHA1="db71823841ffab5bb41341576e7adaaeceddef1c"
        fi
        echo
    fi
    
    if [[ $OSVer != "Other" ]]; then
        IPSW="${IPSWType}_${OSVer}_${BuildVer}_Restore"
        IPSWCustom="${IPSWType}_${OSVer}_${BuildVer}_Custom"

        if [[ $Jailbreak != 1 && $platform == "win" ]]; then
            if [[ $DeviceProc == 7 ]]; then
                IPSWCustomW=2
            else
                IPSWCustom="${IPSWCustom}W"
                IPSWCustomW=1
            fi
        fi

        if [[ ! -e "$IPSWCustom.ipsw" ]] &&
           [[ ! -z $Jailbreak || ! -z $IPSWCustomW ]]; then
            Verify=1
        elif [[ -z $Jailbreak && -z $IPSWCustomW ]]; then
            Verify=1
        fi

        if [[ $Jailbreak == 1 || $IPSWCustomW == 1 ]] &&
           [[ $Verify == 1 && $platform != "win" ]]; then
            Input "Memory Option for creating custom IPSW"
            Echo "* This option makes creating the custom IPSW faster, but it requires at least 8GB of RAM."
            Echo "* If you do not have enough RAM, disable this option and make sure that you have enough storage space."
            Echo "* This option is enabled by default (Y)."
            read -p "$(Input 'Enable this option? (Y/n):')" JBMemory
            echo
        fi

        [[ $IPSWCustomW != 2 ]] && SaveOTABlobs

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

    if [[ $Jailbreak == 1 || $IPSWCustomW == 1 ]]; then
        IPSW32
        IPSWExtract="$IPSWCustom"
    else
        IPSWExtract="$IPSW"
    fi

    Log "Extracting IPSW: $IPSWExtract.ipsw"
    unzip -oq "$IPSWExtract.ipsw" -d "$IPSWExtract"/

    if [[ $IPSWCustomW == 2 ]]; then
        IPSW64
        pwnREC
        local APNonce=$($irecovery -q | grep "NONC" | cut -c 7-)
        Log "APNonce: $APNonce"
        SaveOTABlobs $APNonce
    elif [[ $Jailbreak != 1 && $OSVer != "Other" && $IPSWCustomW != 1 ]]; then
        Log "Preparing for futurerestore... (Enter root password of your PC/Mac when prompted)"
        cd resources
        [[ $platform == "linux" ]] && $SimpleHTTPServer || $SimpleHTTPServer &
        ServerRunning=1
        cd ..
    fi
    
    if [[ ! $IPSWRestore ]]; then
        Log "Setting restore IPSW to: $IPSW.ipsw"
        IPSWRestore="$IPSW"
    fi
    
    if [[ $Jailbreak == 1 || $IPSWCustomW == 1 ]]; then
        iDeviceRestore
    else
        FutureRestore
    fi
    
    echo
    Log "Restoring done!"
    Log "Downgrade script done!"
}
