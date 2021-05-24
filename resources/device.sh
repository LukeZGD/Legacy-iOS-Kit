#!/bin/bash

CheckDeviceState() {
    # CheckDeviceState - Checks the device state (depending on device, must be in normal, recovery, or DFU mode)
    # This is used on the Main function and others
    
    Log "Device: Finding device in normal mode..."
    ideviceinfo2=$($ideviceinfo -s)
    if [[ $? != 0 ]]; then
        Log "Finding device in DFU/recovery mode..."
        DeviceState=$($irecovery -q 2>/dev/null | grep 'MODE' | cut -c 7-) # Changed irecovery2 to DeviceState
    else
        DeviceState="Normal"
    fi
    Log "Device: Found device in $DeviceState mode."
}

FindDevice() {
    # FindDevice - Function to find device in DFU/recovery
    # Argument ($1) should be either "DFU" or "Recovery"
    
    local USB
    [[ $1 == "DFU" ]] && USB=1227 || USB=1289
    
    Log "Device: Finding device in $1 mode..."
    while [[ $DeviceState != "DFU" ]]; do
        [[ $platform == "linux" ]] && DeviceState=$(lsusb | grep -c $USB)
        [[ $platform == "macos" && $($irecovery -q 2>/dev/null | grep "MODE" | cut -c 7-) == "$1" ]] && DeviceState=1
        [[ $DeviceState == 1 ]] && DeviceState="$1"
        sleep 1
    done
    Log "Device: Found device in $1 mode."
}

GetDeviceValues() {
    # GetDeviceValues - Get the device values using irecovery and/or ideviceinfo
    # Also set baseband and other values depending on the detected device
    # It is also used to check if the device is supported or not
    # This is used on the Main function
    
    if [[ $DeviceState == "DFU" || $DeviceState == "Recovery" ]]; then
        ProductType=$($irecovery -q | grep 'PTYP' | cut -c 7-)
        
        # If not on Linux, user must enter ProductType manually
        if [ ! $ProductType ]; then
            read -p "[Input] Enter ProductType (eg. iPad2,1): " ProductType
        fi
        
        UniqueChipID=$((16#$(echo $($irecovery -q | grep 'ECID' | cut -c 7-) | cut -c 3-)))
        ProductVer="Unknown"
        
        # Inform user on how to exit recovery
        if [[ $DeviceState == "Recovery" ]]; then
            Echo "* Your $ProductType is currently in recovery mode."
            Echo "* If you want to exit recovery, select Downgrade device, then select N to exit recovery"
        fi
    else
        ProductType=$(echo "$ideviceinfo2" | grep 'ProductType' | cut -c 14-)
        [[ ! $ProductType ]] && ProductType=$($ideviceinfo | grep 'ProductType' | cut -c 14-)
        ProductVer=$(echo "$ideviceinfo2" | grep 'ProductVer' | cut -c 17-)
        VersionDetect=$(echo $ProductVer | cut -c 1)
        UniqueChipID=$(echo "$ideviceinfo2" | grep 'UniqueChipID' | cut -c 15-)
        UniqueDeviceID=$(echo "$ideviceinfo2" | grep 'UniqueDeviceID' | cut -c 17-)
    fi
    
    if [[ ! $ProductType ]]; then
        Error "No device detected. Please put the device in normal mode (and jailbroken for 32-bit) before proceeding" \
        "Recovery or DFU mode is also applicable for A7 devices"
    fi
    
    Baseband=0
    Firmware=resources/firmware/$ProductType
    BasebandURL=$(cat $Firmware/13G37/url 2>/dev/null) # iOS 9.3.6
    
    if [[ $ProductType == "iPad2,2" ]]; then
        BasebandURL=$(cat $Firmware/13G36/url) # iOS 9.3.5
        Baseband="ICE3_04.12.09_BOOT_02.13.Release.bbfw"
        BasebandSHA1="e6f54acc5d5652d39a0ef9af5589681df39e0aca"
        
    elif [[ $ProductType == "iPad2,3" ]]; then
        Baseband="Phoenix-3.6.03.Release.bbfw"
        BasebandSHA1="8d4efb2214344ea8e7c9305392068ab0a7168ba4"
        
    elif [[ $ProductType == "iPad2,6" || $ProductType == "iPad2,7" ]]; then
        Baseband="Mav5-11.80.00.Release.bbfw"
        BasebandSHA1="aa52cf75b82fc686f94772e216008345b6a2a750"
        
    elif [[ $ProductType == "iPad3,2" || $ProductType == "iPad3,3" ]]; then
        Baseband="Mav4-6.7.00.Release.bbfw"
        BasebandSHA1="a5d6978ecead8d9c056250ad4622db4d6c71d15e"
        
    elif [[ $ProductType == "iPhone4,1" ]]; then
        Baseband="Trek-6.7.00.Release.bbfw"
        BasebandSHA1="22a35425a3cdf8fa1458b5116cfb199448eecf49"
        
    elif [[ $ProductType == "iPad3,5" || $ProductType == "iPad3,6" ||
            $ProductType == "iPhone5,1" || $ProductType == "iPhone5,2" ]]; then
        BasebandURL=$(cat $Firmware/14G61/url) # iOS 10.3.4
        Baseband="Mav5-11.80.00.Release.bbfw"
        BasebandSHA1="8951cf09f16029c5c0533e951eb4c06609d0ba7f"
        
    elif [[ $ProductType == "iPad4,2" || $ProductType == "iPad4,3" || $ProductType == "iPad4,5" ||
            $ProductType == "iPhone6,1" || $ProductType == "iPhone6,2" ]]; then
        BasebandURL=$(cat $Firmware/14G60/url)
        Baseband="Mav7Mav8-7.60.00.Release.bbfw"
        BasebandSHA1="f397724367f6bed459cf8f3d523553c13e8ae12c"
        
    elif [[ $ProductType != "iPad2"* && $ProductType != "iPad3"* &&
            $ProductType != "iPod5,1" && $ProductType != "iPhone5"* ]]; then
        Error "Your device $ProductType is not supported."
    fi
    
    if [[ $ProductType == "iPad2"* || $ProductType == "iPad3,1" ||
          $ProductType == "iPad3,2" || $ProductType == "iPad3,3" ||
          $ProductType == "iPhone4,1" || $ProductType == "iPod5,1" ]]; then
        DeviceProc=5
    elif [[ $ProductType == "iPad3,4" || $ProductType == "iPad3,5" ||
            $ProductType == "iPad3,6" || $ProductType == "iPhone5"* ]]; then
        DeviceProc=6
    elif [[ $ProductType == "iPhone6"* || $ProductType == "iPad4"* ]]; then
        DeviceProc=7
    fi
} 
