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

FutureRestore() {
    local ExtraArgs=("--use-pwndfu")

    Log "Proceeding to futurerestore..."
    [[ $platform == "linux" ]] && Echo "* Enter your user password when prompted"
    cd resources
    $SimpleHTTPServer &
    ServerPID=$!
    cd ..

    if [[ $DeviceProc == 7 ]]; then
        # Send dummy file for device detection
        $irecovery -f README.md
        sleep 2
        ExtraArgs+=("-s" "$IPSWRestore/Firmware/all_flash/$SEP" "-m" "$BuildManifest")
    elif [[ $SendiBSS != 1 ]]; then
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

    Log "Running futurerestore with command: $futurerestore -t \"$SHSH\" ${ExtraArgs[*]} \"$IPSWRestore.ipsw\""
    $futurerestore -t "$SHSH" "${ExtraArgs[@]}" "$IPSWRestore.ipsw"
    if [[ $? != 0 ]]; then
        Log "An error seems to have occurred in futurerestore."
        Echo "* Please read the \"Troubleshooting\" wiki page in GitHub before opening any issue!"
        Echo "* Your problem may have already been addressed within the wiki page."
        Echo "* If opening an issue in GitHub, please provide a FULL log. Otherwise, your issue may be dismissed."
    else
        echo
        Log "Restoring done!"
    fi
    Log "Downgrade script done!"
}

DowngradeOther() {
    Input "Select your IPSW file in the file selection window."
    IPSW="$($zenity --file-selection --file-filter='IPSW | *.ipsw' --title="Select IPSW file")"
    [[ ! -s "$IPSW" ]] && Error "No IPSW selected, or IPSW file not found."
    IPSW="${IPSW%?????}"
    Log "Selected IPSW file: $IPSW.ipsw"
    Input "Select your SHSH file in the file selection window."
    SHSH="$($zenity --file-selection --file-filter='SHSH | *.shsh *.shsh2' --title="Select SHSH file")"
    [[ ! -s "$SHSH" ]] && Error "No SHSH selected, or SHSH file not found."
    Log "Selected SHSH file: $SHSH"

    if [[ ! -e resources/firmware/$ProductType/$BuildVer/index.html ]]; then
        unzip -o -j "$IPSW.ipsw" Restore.plist -d tmp
        BuildVer=$(cat tmp/Restore.plist | grep -i ProductBuildVersion -A 1 | grep -oPm1 "(?<=<string>)[^<]+")
        Log "Getting firmware keys for $ProductType-$BuildVer"
        mkdir -p resources/firmware/$ProductType/$BuildVer 2>/dev/null
        curl -L https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/raw/master/$ProductType/$BuildVer/index.html -o tmp/index.html
        mv tmp/index.html resources/firmware/$ProductType/$BuildVer
    fi

    kDFU
    IPSWSetExtract
    FutureRestore
}

DowngradeOTA() {
    [[ $DeviceProc != 7 ]] && JailbreakOption
    SaveOTABlobs
    IPSWFindVerify
    kDFU
    [[ $Jailbreak == 1 ]] && IPSW32
    IPSWSetExtract
    FutureRestore
}

Downgrade() {
    Log "Select your options when asked. If unsure, go for the defaults (press Enter/Return)."
    echo
    if [[ $OSVer == "Other" ]]; then
        DowngradeOther
        return
    fi
    DowngradeOTA
}
