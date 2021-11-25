#!/bin/bash
trap "Clean" EXIT
trap "Clean; exit 1" INT TERM

cd "$(dirname $0)"
. ./resources/blobs.sh
. ./resources/depends.sh
. ./resources/device.sh
. ./resources/downgrade.sh
. ./resources/ipsw.sh

if [[ $1 != "NoColor" && $2 != "NoColor" ]]; then
    TERM=xterm-256color
    Color_R=$(tput setaf 9)
    Color_G=$(tput setaf 10)
    Color_B=$(tput setaf 12)
    Color_Y=$(tput setaf 11)
    Color_N=$(tput sgr0)
fi

Clean() {
    rm -rf iP*/ shsh/ tmp/ *.im4p *.bbfw ${UniqueChipID}_${ProductType}_*.shsh2 \
    ${UniqueChipID}_${ProductType}_${HWModel}ap_*.shsh BuildManifest.plist
    kill $iproxyPID $ServerPID 2>/dev/null
}

Echo() {
    echo "${Color_B}$1 ${Color_N}"
}

Error() {
    echo -e "\n${Color_R}[Error] $1 ${Color_N}"
    [[ -n $2 ]] && echo "${Color_R}* $2 ${Color_N}"
    echo
    exit 1
}

Input() {
    echo "${Color_Y}[Input] $1 ${Color_N}"
}

Log() {
    echo "${Color_G}[Log] $1 ${Color_N}"
}

Main() {
    local Selection=()
    
    clear
    Echo "******* iOS-OTA-Downgrader *******"
    Echo "   Downgrader script by LukeZGD   "
    echo
    
    if [[ $EUID == 0 ]]; then
        Error "Running the script as root is not allowed."
    fi

    if [[ ! -d ./resources ]]; then
        Error "resources folder cannot be found. Replace resources folder and try again." \
        "If resources folder is present try removing spaces from path/folder name"
    fi
    
    SetToolPaths
    if [[ $? != 0 ]]; then
        Error "Setting tool paths failed. Your copy of iOS-OTA-Downgrader seems to be incomplete."
    fi
    
    if [[ ! $platform ]]; then
        Error "Platform unknown/not supported."
    fi
    
    chmod +x ./resources/*.sh ./resources/tools/*
    if [[ $? != 0 ]]; then
        Error "A problem with file permissions has been detected, cannot proceed."
    fi
    
    Log "Checking Internet connection..."
    ping -c1 8.8.8.8 >/dev/null
    if [[ $? != 0 ]]; then
        Error "Please check your Internet connection before proceeding."
    fi
    
    if [[ $platform == "macos" && $(uname -m) != "x86_64" ]]; then
        Log "Apple Silicon Mac detected. Support may be limited, proceed at your own risk."
    elif [[ $(uname -m) != "x86_64" ]]; then
        Error "Only 64-bit (x86_64) distributions are supported."
    fi

    if [[ $1 == "Install" || -z $bspatch || ! -e $ideviceinfo || ! -e $irecoverychk ||
          ! -e $ideviceenterrecovery || ! -e $iproxy || -z $python ||
          ! -d ./resources/libimobiledevice_$platform ]]; then
        if [[ ! -e $ideviceinfo || ! -e $irecoverychk ||
              ! -e $ideviceenterrecovery || ! -e $iproxy ]]; then
            rm -rf ./resources/libimobiledevice_$platform
        fi
        Clean
        InstallDepends
    fi
    
    SaveExternal LukeZGD ipwndfu

    GetDeviceValues $1
    
    Clean
    mkdir tmp

    if [[ -n $1 && $1 != "NoColor" && $1 != "NoDevice" && $1 != "PwnedDevice" ]]; then
        Mode="$1"
    else
        [[ $1 != "NoDevice" ]] && Selection+=("Downgrade Device")
        Selection+=("Save OTA Blobs")
        if [[ $DeviceProc != 7 ]]; then
            Selection+=("Create Custom IPSW")
            [[ $DeviceState == "Normal" ]] && Selection+=("Put Device in kDFU Mode")
        fi
        Selection+=("(Re-)Install Dependencies" "(Any other key to exit)")
        Echo "*** Main Menu ***"
        Input "Select an option:"
        select opt in "${Selection[@]}"; do
        case $opt in
            "Downgrade Device" ) Mode="Downgrade"; break;;
            "Save OTA Blobs" ) Mode="SaveOTABlobs"; break;;
            "Create Custom IPSW" ) Mode="IPSW32"; break;;
            "Put Device in kDFU Mode" ) Mode="kDFU"; break;;
            "(Re-)Install Dependencies" ) InstallDepends;;
            * ) exit 0;;
        esac
        done
    fi

    SelectVersion

    if [[ $Mode == "IPSW32" ]]; then
        IPSW="${IPSWType}_${OSVer}_${BuildVer}_Restore"
        IPSWCustom="${IPSWType}_${OSVer}_${BuildVer}_Custom"
        Verify=1
        echo
        JailbreakSet
        Log "Using $JBName for the jailbreak"
        MemoryOption
        IPSW32
        Log "Custom IPSW has been created: $IPSWCustom.ipsw"
        Echo "* This custom IPSW has a jailbreak built in ($JBName)"
        Echo "* Run the script again and select Downgrade Device to use the custom IPSW."
        Echo "* You may also use futurerestore manually (make sure to use the latest beta)"
        exit 0

    elif [[ $Mode != "Downgrade" ]]; then
        $Mode
        exit 0
    fi

    if [[ $DeviceProc == 7 ]]; then
        if [[ $DeviceState == "Normal" ]]; then
            Echo "* The device needs to be in recovery/DFU mode before proceeding."
            read -p "$(Input 'Send device to recovery mode? (y/N):')" Selection
            [[ $Selection == 'Y' || $Selection == 'y' ]] && Recovery || exit
        elif [[ $DeviceState == "Recovery" ]]; then
            Recovery
        elif [[ $DeviceState == "DFU" ]]; then
            CheckM8
        fi
    
    elif [[ $DeviceState == "DFU" ]]; then
        if [[ $1 != "PwnedDevice" ]]; then
            echo -e "\n${Color_R}[Error] 32-bit A${DeviceProc} device detected in DFU mode. ${Color_N}"
            echo "${Color_Y}* Please put the device in normal mode and jailbroken before proceeding. ${Color_N}"
            echo "${Color_Y}* Exit DFU mode by holding the TOP and HOME buttons for 15 seconds. ${Color_N}"
            echo "${Color_Y}* For usage of the DFU Advanced Menu, add PwnedDevice as an argument. ${Color_N}"
            echo "${Color_Y}* For more details, read the \"Troubleshooting\" wiki page in GitHub ${Color_N}"
            exit 1
        fi
        Mode="Downgrade"
        echo
        Echo "* DFU Advanced Menu"
        Echo "* This menu is for ADVANCED USERS ONLY."
        Echo "* If you do not know what you are doing, EXIT NOW by pressing Ctrl+C and restart your device in normal mode."
        Input "Select the mode that your device is currently in:"
        Selection=("kDFU mode")
        [[ $DeviceProc == 5 ]] && Selection+=("pwnDFU mode (A5)")
        [[ $DeviceProc == 6 ]] && Selection+=("DFU mode (A6)")
        Selection+=("Any other key to exit")
        select opt in "${Selection[@]}"; do
        case $opt in
            "kDFU mode" ) break;;
            "DFU mode (A6)" ) CheckM8; break;;
            "pwnDFU mode (A5)" )
                Echo "* Make sure that your device is in pwnDFU mode using an Arduino+USB Host Shield!";
                Echo "* This option will not work if your device is not in pwnDFU mode.";
                Input "Press Enter/Return to continue (or press Ctrl+C to cancel)";
                read -s;
                kDFU iBSS; break;;
            * ) exit 0;;
        esac
        done
        Log "Downgrading $ProductType in kDFU/pwnDFU mode..."
    
    elif [[ $DeviceState == "Recovery" ]]; then
        if [[ $DeviceProc == 6 ]]; then
            Recovery
        else
            Log "32-bit A${DeviceProc} device detected in recovery mode."
            Echo "* Please put the device in normal mode and jailbroken before proceeding."
            Echo "* For usage of the DFU Advanced Menu, put the device in kDFU or pwnDFU mode"
            RecoveryExit
        fi
        Log "Downgrading $ProductType in pwnDFU mode..."
    fi
    
    Downgrade
    exit 0
}

SelectVersion() {
    if [[ $Mode == "kDFU" ]]; then
        return
    elif [[ $ProductType == "iPad4"* || $ProductType == "iPhone6"* ]]; then
        OSVer="10.3.3"
        BuildVer="14G60"
        return
    fi
    
    if [[ $ProductType == "iPhone5,3" || $ProductType == "iPhone5,4" ]]; then
        Selection=()
    else
        Selection=("iOS 8.4.1")
    fi
    
    if [[ $ProductType == "iPad2,1" || $ProductType == "iPad2,2" ||
          $ProductType == "iPad2,3" || $ProductType == "iPhone4,1" ]]; then
        Selection+=("iOS 6.1.3")
    fi
    
    [[ $Mode == "Downgrade" ]] && Selection+=("Other (use SHSH blobs)")
    Selection+=("(Any other key to exit)")
    
    echo
    Input "Select iOS version:"
    select opt in "${Selection[@]}"; do
    case $opt in
        "iOS 8.4.1" ) OSVer="8.4.1"; BuildVer="12H321"; break;;
        "iOS 6.1.3" ) OSVer="6.1.3"; BuildVer="10B329"; break;;
        "Other (use SHSH blobs)" ) OSVer="Other"; break;;
        *) exit 0;;
    esac
    done
}

Main $1
