#!/bin/bash
trap 'Clean; exit' INT TERM EXIT

. ./resources/blobs.sh
. ./resources/depends.sh
. ./resources/device.sh
. ./resources/devicestate.sh
. ./resources/downgrade.sh
. ./resources/ipsw.sh

if [[ $1 != 'NoColor' ]] && [[ $2 != 'NoColor' ]]; then
    Color_R=$(tput setaf 9)
    Color_G=$(tput setaf 10)
    Color_B=$(tput setaf 12)
    Color_Y=$(tput setaf 11)
    Color_N=$(tput sgr0)
fi

Clean() {
    rm -rf iP*/ shsh/ tmp/ ${UniqueChipID}_${ProductType}_*.shsh2 ${UniqueChipID}_${ProductType}_${HWModel}ap_*.shsh *.im4p *.bbfw BuildManifest.plist
}

Echo() {
    echo "${Color_B}$1 ${Color_N}"
}

Error() {
    echo -e "\n${Color_R}[Error] $1 ${Color_N}"
    [[ ! -z $2 ]] && echo "${Color_R}* $2 ${Color_N}"
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
    clear
    Echo "******* iOS-OTA-Downgrader *******"
    Echo "   Downgrader script by LukeZGD   "
    echo
    
    # Run SetToolPaths from depends
    SetToolPaths
    
    # Check platform value (must be "macos" or "linux")
    if [[ ! $platform ]]; then
        Error "Platform unknown/not supported."
    fi
    
    # Check resources folder
    if [[ ! -d resources ]]; then
        Error "resources folder cannot be found. Replace resources folder and try again" \
        "If resources folder is present try removing spaces from path/folder name"
    fi
    
    # Mark all in resources/modules and resources/tools as executable
    chmod +x ./resources/*.sh ./resources/tools/*
    if [[ $? == 1 ]]; then
        # If chmod failed, warn the user
        Log "An error occurred in chmod. This might cause problems..."
    fi
    
    # Internet connection check
    if [[ ! $(ping -c1 1.1.1.1 2>/dev/null) ]]; then
        Error "Please check your Internet connection before proceeding."
    fi
    
    # Check uname value (must be "x86_64", warn if platform is "macos" and not "x86_64")
    if [[ $platform == macos && $(uname -m) != 'x86_64' ]]; then
        Log "M1 Mac detected. Support is limited, the script may or may not work for you"
        Echo "* M1 macs can still proceed but I cannot support it if things break"
        Echo "* Proceed at your own risk."
        Input "Press Enter/Return to continue (or press Ctrl+C to cancel)"
        read -s
    elif [[ $(uname -m) != 'x86_64' ]]; then
        Error "Only x86_64 distributions are supported. Use a 64-bit distro and try again"
    fi
    
    # Check dependencies, if one or more are missing (or if manually specified), run InstallDependencies from depends
    if [[ $1 == "Install" || ! $bspatch || ! $git ||
          ! $ideviceinfo || ! $irecoverychk || ! $python ]]; then
        InstallDependencies
    fi
    
    # Get needed stuff, run SaveExternal from depends
    SaveExternal iOS-OTA-Downgrader-Keys
    SaveExternal ipwndfu
    
    # Run functions from device
    CheckDeviceState
    GetDeviceValues
    
    # Run function from firmware
    BasebandDetect
    
    # Cleanup
    Clean
    mkdir tmp
    
    if [[ $DeviceProc == 7 ]]; then
    elif [[ $DeviceState == "DFU" ]]; then
        # Advanced options menu for 32-bit devices
        DFUManual=1
        Mode="Downgrade"
        Echo "* Advanced Options Menu"
        Input "This device is in:"
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
                Echo "* This option will NOT work if your device is not in pwnDFU mode.";
                Input "Press Enter/Return to continue (or press Ctrl+C to cancel)";
                read -s;
                kDFU iBSS; break;;
            * ) exit;;
        esac
        done
        Log "Downgrading $ProductType in kDFU/pwnDFU mode..."
        SkipMainMenu=1
    
    elif [[ $DeviceState == "Recovery" ]]; then
        if [[ $DeviceProc == 6 ]]; then
            Recovery
        else
            Error "32-bit A5 device detected in recovery mode. Please put the device in normal mode and jailbroken before proceeding" \
            "For usage of advanced DFU options, put the device in pwnDFU mode using Arduino + USB Host Shield"
        fi
    fi
    
    [[ ! -z $1 ]] && SkipMainMenu=1
    
    if [[ ! -z $1 ]] && [[ $1 != "NoColor" ]]; then
        # Skip main menu if argument passed
        Mode="$1"
    else
        # Main Menu!
        Selection=("Downgrade device")
    
        # Only show these options for 32-bit devices
        [[ $DeviceProc != 7 ]] && Selection+=("Save OTA blobs" "Just put device in kDFU mode")
    
        Selection+=("(Re-)Install Dependencies" "(Any other key to exit)")
        Echo "*** Main Menu ***"
        Input "Select an option:"
        select opt in "${Selection[@]}"; do
        case $opt in
            "Downgrade device" ) Mode="Downgrade"; break;;
            "Save OTA blobs" ) Mode="SaveOTABlobs"; break;;
            "Just put device in kDFU mode" ) Mode="kDFU"; break;;
            "(Re-)Install Dependencies" ) InstallDependencies;;
            * ) exit;;
        esac
        done
    fi
    
    SelectVersion
    
    Log "Option: $Mode"
    [[ $Mode == 'Downgrade' ]] && Downgrade # run from downgrade
    [[ $Mode == 'SaveOTABlobs' ]] && SaveOTABlobs # run from blobs
    [[ $Mode == 'kDFU' ]] && kDFU # run from devicestate
    exit
}

SelectVersion() {
    if [[ $ProductType == "iPad4"* || $ProductType == iPhone6* || $Mode == "kDFU" ]]; then
        OSVer="10.3.3"
        BuildVer="14G60"
        return
    fi
    
    if [[ $ProductType == "iPhone5,3" || $ProductType == "iPhone5,4" ]]; then
        # Do not show 8.4.1 option for 5C devices
        Selection=()
    else
        # Add 8.4.1 to version list
        Selection=("iOS 8.4.1")
    fi
    
    if [[ $ProductType == "iPad2,1" || $ProductType == "iPad2,2" ||
          $ProductType == "iPad2,3" || $ProductType == "iPhone4,1" ]]; then
        # Only add 6.1.3 to version list if device is iPad 2 or iPhone 4S
        Selection+=("iOS 6.1.3")
    fi
    
    # Finally, add "Other" and exit option to list (only if in Downgrade mode)
    [[ $Mode == "Downgrade" ]] && Selection+=("Other (use SHSH blobs)")
    Selection+=("(Any other key to exit)")
    
    Input "Select iOS version:"
    select opt in "${Selection[@]}"; do
        case $opt in
            "iOS 8.4.1" ) OSVer="8.4.1"; BuildVer="12H321"; break;;
            "iOS 6.1.3" ) OSVer="6.1.3"; BuildVer="10B329"; break;;
            "Other (use SHSH blobs)" ) OSVer="Other"; break;;
            *) exit;;
        esac
    done
}

cd "$(dirname $0)"
Main $1
