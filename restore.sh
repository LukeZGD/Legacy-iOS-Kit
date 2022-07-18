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
    ${UniqueChipID}_${ProductType}_${HWModel}ap_*.shsh BuildManifest.plist version.xml
    kill $iproxyPID $ServerPID 2>/dev/null
}

Echo() {
    echo "${Color_B}$1 ${Color_N}"
}

Error() {
    echo -e "\n${Color_R}[Error] $1 ${Color_N}"
    [[ -n $2 ]] && echo "${Color_R}* $2 ${Color_N}"
    echo
    ExitWin 1
}

Input() {
    echo "${Color_Y}[Input] $1 ${Color_N}"
}

Log() {
    echo "${Color_G}[Log] $1 ${Color_N}"
}

ExitWin() {
    if [[ $platform == "win" ]]; then
        echo
        Input "Press Enter/Return to exit."
        read -s
    fi
    exit $1
}

Main() {
    local Selection=()
    
    clear
    Echo "******* iOS-OTA-Downgrader *******"
    Echo " - Downgrader script by LukeZGD - "
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
    $ping 8.8.8.8 >/dev/null
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
          ! -e ./resources/first_run ]]; then
        if [[ ! -e $ideviceinfo || ! -e $irecoverychk ||
              ! -e $ideviceenterrecovery || ! -e $iproxy ]]; then
            rm -rf ./resources/libimobiledevice_$platform
        fi
        Clean
        InstallDepends
    fi
    
    GetDeviceValues $1
    Clean
    mkdir tmp

    if [[ $ProductType == "iPhone3,1" ]]; then
        SaveExternal ch3rryflower
    fi

    if [[ -n $1 && $1 != "NoColor" && $1 != "NoDevice" && $1 != "PwnedDevice" ]]; then
        Mode="$1"
    else
        [[ $1 != "NoDevice" ]] && Selection+=("Downgrade Device")
        [[ $DeviceProc != 4 ]] && Selection+=("Save OTA Blobs")

        if [[ $ProductType == "iPhone3,1" && $1 != "NoDevice" ]]; then
            Selection+=("Disable/Enable Exploit" "Restore to 7.1.2" "SSH Ramdisk")
        fi

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
            "Disable/Enable Exploit" ) Mode="Remove4"; break;;
            "Restore to 7.1.2" ) Mode="Restore712"; break;;
            "SSH Ramdisk" ) Mode="Ramdisk4"; break;;
            "(Re-)Install Dependencies" ) InstallDepends;;
            * ) exit 0;;
        esac
        done
    fi

    SelectVersion
    [[ $OSVer == "Other" ]] && Mode="Downgrade"

    if [[ $Mode == "IPSW32" ]]; then
        echo
        [[ $platform == "win" ]] && IPSWCustom="${IPSWType}_${OSVer}_${BuildVer}_CustomWin"
        JailbreakOption
        if [[ -e "$IPSWCustom.ipsw" ]]; then
            Log "Found existing Custom IPSW, stopping here."
            Echo "* If you want to re-create the custom IPSW, move/delete the existing one first."
            ExitWin 0
        elif [[ $Jailbreak != 1 && $platform != "win" ]]; then
            if [[ $DeviceProc == 4 && $OSVer == "7.1.2" ]]; then
                Log "Creating custom IPSW is not needed for non-jailbroken 7.1.2 restores."
                ExitWin 0
            elif [[ $ProductType != "iPhone3"* && $ProductType != "iPad2,3" ]]; then
                Log "Creating custom IPSW is not needed for non-jailbroken restores on your device."
                ExitWin 0
            fi
        fi

        IPSWFindVerify
        if [[ $DeviceProc == 4 ]]; then
            [[ $OSVer != "7.1.2" ]] && IPSWFindVerify 712
            IPSW4
        else
            IPSW32
        fi
        Log "Custom IPSW has been created: $IPSWCustom.ipsw"
        [[ $Jailbreak == 1 ]] && Echo "* This custom IPSW has a jailbreak built in ($JBName)"
        Echo "* Run the script again and select Downgrade Device to use the custom IPSW."
        if [[ $DeviceProc != 4 && $platform != "win" ]]; then
            Echo "* You may also use futurerestore manually (make sure to use the latest beta)"
        fi
        ExitWin 0

    elif [[ $Mode != "Downgrade"* && $Mode != *"4" ]]; then
        $Mode
        ExitWin 0
    fi

    if [[ $DeviceProc == 4 && $platform == "win" ]]; then
        Error "Your device ($ProductType) is unsupported on Windows."
    elif [[ $DeviceProc == 7 && $platform == "win" ]]; then
        local Message="If you want to restore your A7 device on Windows, put the device in pwnDFU mode."
        if [[ $DeviceState == "Normal" ]]; then
            Error "$Message"
        elif [[ $DeviceState == "Recovery" ]]; then
            Log "A7 device detected in recovery mode."
            Log "$Message"
            RecoveryExit
        elif [[ $DeviceState == "DFU" ]]; then
            Log "A7 device detected in DFU mode."
            Echo "* Make sure that your device is already in pwnDFU mode with signature checks disabled."
            Echo "* If your device is not in pwnDFU mode, the restore will not proceed!"
            Echo "* Entering pwnDFU mode is not supported on Windows. You need to use a Mac/Linux machine or another iOS device to do so."
            Input "Press Enter/Return to continue (or press Ctrl+C to cancel)"
            read -s
        fi

    elif [[ $Mode == *"4" || $DeviceProc == 7 ]]; then
        if [[ $DeviceState == "Normal" && $OSVer == "7.1.2" ]]; then
            kDFU
        elif [[ $DeviceState == "DFU" && $OSVer == "7.1.2" ]]; then
            Input "Select the mode that your device is currently in:"
            Selection=("kDFU mode" "DFU/pwnDFU mode")
            select opt in "${Selection[@]}"; do
            case $opt in
                "kDFU mode" ) break;;
                "DFU/pwnDFU mode" ) EnterPwnDFU; break;;
                * ) exit 0;;
            esac
            done
        elif [[ $DeviceState == "Normal" ]]; then
            Echo "* The device needs to be in recovery/DFU mode before proceeding."
            read -p "$(Input 'Send device to recovery mode? (y/N):')" Selection
            [[ $Selection == 'Y' || $Selection == 'y' ]] && Recovery || exit
        elif [[ $DeviceState == "Recovery" ]]; then
            Recovery
        elif [[ $DeviceState == "DFU" ]]; then
            EnterPwnDFU
        fi
        if [[ $Mode == *"4" ]]; then
            $Mode
            exit 0
        fi

    elif [[ $DeviceState == "DFU" ]]; then
        if [[ $1 != "PwnedDevice" ]]; then
            echo -e "\n${Color_R}[Error] 32-bit A${DeviceProc} device detected in DFU mode. ${Color_N}"
            echo "${Color_Y}* Please put the device in normal mode and jailbroken before proceeding. ${Color_N}"
            echo "${Color_Y}* Exit DFU mode by holding the TOP and HOME buttons for 15 seconds. ${Color_N}"
            echo "${Color_Y}* For usage of the DFU Advanced Menu, add PwnedDevice as an argument. ${Color_N}"
            echo "${Color_Y}* For more details, read the \"Troubleshooting\" wiki page in GitHub ${Color_N}"
            ExitWin 1
        fi
        echo
        Echo "* DFU Advanced Menu"
        Echo "* This menu is for ADVANCED USERS ONLY."
        Echo "* If you do not know what you are doing, EXIT NOW by pressing Ctrl+C and restart your device in normal mode."
        Input "Select the mode that your device is currently in:"
        Selection=("kDFU mode")
        if [[ $platform != "win" ]]; then
            [[ $DeviceProc == 5 ]] && Selection+=("pwnDFU mode (A5)") || Selection+=("DFU mode (A4/A6)")
        fi
        Selection+=("Any other key to exit")
        select opt in "${Selection[@]}"; do
        case $opt in
            "kDFU mode" ) break;;
            "DFU mode (A4/A6)" ) EnterPwnDFU; break;;
            "pwnDFU mode (A5)" ) SendPwnediBSSA5; break;;
            * ) exit 0;;
        esac
        done
        Log "Downgrading $ProductType in kDFU/pwnDFU mode..."
    
    elif [[ $DeviceState == "Recovery" ]]; then
        if [[ $DeviceProc == 4 || $DeviceProc == 6 ]] && [[ $platform != "win" ]]; then
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
    ExitWin 0
}

SelectVersion() {
    if [[ $DeviceProc == 7 ]]; then
        OSVer="10.3.3"
        BuildVer="14G60"
        return
    elif [[ $Mode == "Downgrade"* ]]; then
        :
    elif [[ $Mode == "kDFU" || $Mode == *"4" ]]; then
        return
    fi
    
    if [[ $ProductType == "iPhone5,3" || $ProductType == "iPhone5,4" || $ProductType == "iPhone3"* ]]; then
        Selection=()
    else
        Selection=("iOS 8.4.1")
    fi
    
    if [[ $ProductType == "iPad2,1" || $ProductType == "iPad2,2" ||
          $ProductType == "iPad2,3" || $ProductType == "iPhone4,1" ]]; then
        Selection+=("iOS 6.1.3")
    fi

    if [[ $ProductType == "iPhone3,1" ]]; then
        [[ $Mode == "IPSW32" ]] && Selection+=("7.1.2")
        Selection+=("6.1.3" "5.1.1 (9B208)" "5.1.1 (9B206)" "4.3.5" "More versions (4.3-6.1.2)")
        Selection2=("6.1.2" "6.1" "6.0.1" "6.0" "5.1" "5.0.1" "5.0" "4.3.3" "4.3")
        if [[ $Mode == "Restore712" ]]; then
            Echo "* Make sure to disable the exploit first! See the README for more details."
            Input "Press Enter/Return to continue (or press Ctrl+C to cancel)"
            read -s
            OSVer="7.1.2"
            BuildVer="11D257"
            Mode="Downgrade4"
            return
        elif [[ $Mode == "Downgrade" ]]; then
            Mode="Downgrade4"
        fi
    fi

    if [[ $platform != "win" ]]; then
        [[ $Mode == "Downgrade"* ]] && Selection+=("Other (use SHSH blobs)")
    fi
    Selection+=("(Any other key to exit)")
    
    echo
    Input "Select iOS version:"
    select opt in "${Selection[@]}"; do
    case $opt in
        "iOS 8.4.1" ) OSVer="8.4.1"; BuildVer="12H321"; break;;
        "iOS 6.1.3" ) OSVer="6.1.3"; BuildVer="10B329"; break;;
        "Other (use SHSH blobs)" ) OSVer="Other"; break;;
        "7.1.2" ) OSVer="7.1.2"; BuildVer="11D257"; break;;
        "6.1.3" ) OSVer="6.1.3"; BuildVer="10B329"; break;;
        "5.1.1 (9B208)" ) OSVer="5.1.1"; BuildVer="9B208"; break;;
        "5.1.1 (9B206)" ) OSVer="5.1.1"; BuildVer="9B206"; break;;
        "4.3.5" ) OSVer="4.3.5"; BuildVer="8L1"; break;;
        "More versions (4.3-6.1.2)" ) OSVer="More"; break;;
        * ) exit 0;;
    esac
    done

    if [[ $OSVer == "More" ]]; then
        select opt in "${Selection2[@]}"; do
        case $opt in
            "6.1.2" ) OSVer="6.1.2"; BuildVer="10B146"; break;;
            "6.1" ) OSVer="6.1"; BuildVer="10B144"; break;;
            "6.0.1" ) OSVer="6.0.1"; BuildVer="10A523"; break;;
            "6.0" ) OSVer="6.0"; BuildVer="10A403"; break;;
            "5.1" ) OSVer="5.1"; BuildVer="9B176"; break;;
            "5.0.1" ) OSVer="5.0.1"; BuildVer="9A405"; break;;
            "5.0" ) OSVer="5.0"; BuildVer="9A334"; break;;
            "4.3.3" ) OSVer="4.3.3"; BuildVer="8J2"; break;;
            "4.3" ) OSVer="4.3"; BuildVer="8F190"; break;;
            * ) exit 0;;
        esac
        done
    fi
}

Main $1
