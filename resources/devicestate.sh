#!/bin/bash

kDFU() {
    if [ ! -e saved/$ProductType/$iBSS.dfu ]; then
        Log "Downloading iBSS..."
        $partialzip $(cat $Firmware/$iBSSBuildVer/url) Firmware/dfu/$iBSS.dfu $iBSS.dfu
        mkdir -p saved/$ProductType 2>/dev/null
        mv $iBSS.dfu saved/$ProductType
    fi
    [[ ! -e saved/$ProductType/$iBSS.dfu ]] && Error "Failed to save iBSS. Please run the script again"
    Log "Patching iBSS..."
    $bspatch saved/$ProductType/$iBSS.dfu tmp/pwnediBSS resources/patches/$iBSS.patch
    
    if [[ $1 == iBSS ]]; then
        cd resources/ipwndfu
        Log "Sending iBSS..."
        sudo $python ipwndfu -l ../../tmp/pwnediBSS
        ret=$?
        cd ../..
        return $ret
    fi
    
    [[ $VersionDetect == 1 ]] && kloader='kloader_hgsp'
    [[ $VersionDetect == 5 ]] && kloader='kloader5'
    [[ ! $kloader ]] && kloader='kloader'
    
    [ ! $(which $iproxy) ] && Error "iproxy cannot be found. Please re-install dependencies and try again" "./restore.sh Install"
    $iproxy 2222 22 &
    iproxyPID=$!
    
    Log "Copying stuff to device via SSH..."
    Echo "* Make sure OpenSSH/Dropbear is installed on the device and running!"
    Echo "* Dropbear is only needed for devices on iOS 10"
    Echo "* To make sure that SSH is successful, try these steps:"
    Echo "* Reinstall OpenSSH/Dropbear, reboot and rejailbreak, then reinstall them again"
    echo
    Input "Enter the root password of your iOS device when prompted, default is 'alpine'"
    $SCP -P 2222 resources/tools/$kloader tmp/pwnediBSS root@127.0.0.1:/tmp
    if [ $? == 1 ]; then
        Log "Cannot connect to device via USB SSH."
        Echo "* Please try the steps above to make sure that SSH is successful"
        Input "Press Enter/Return to continue anyway (or press Ctrl+C to cancel and try again)"
        read -s
        Log "Will try again with Wi-Fi SSH..."
        Echo "* Make sure that the device and your PC/Mac are on the same network!"
        Echo "* You can check for your device's IP Address in: Settings > WiFi/WLAN > tap the 'i' next to your network name"
        read -p "$(Input 'Enter the IP Address of your device: ')" IPAddress
        Log "Copying stuff to device via SSH..."
        $SCP resources/tools/$kloader tmp/pwnediBSS root@$IPAddress:/tmp
        [ $? == 1 ] && Error "Cannot connect to device via SSH." "Please try the steps above to make sure that SSH is successful"
        $SSH root@$IPAddress "/tmp/$kloader /tmp/pwnediBSS" &
    else
        $SSH -p 2222 root@127.0.0.1 "/tmp/$kloader /tmp/pwnediBSS" &
    fi
    Log "Entering kDFU mode..."
    echo
    Echo "* Press POWER or HOME button when screen goes black on the device"
    FindDevice "DFU"
    kill $iproxyPID
}

Recovery() {
    local RecoveryDFU
    
    Log "Entering recovery mode..."
    $ideviceenterrecovery $UniqueDeviceID >/dev/null
    FindDevice "Recovery"
    Log "Get ready to enter DFU mode."
    read -p "$(Input 'Select Y to continue, N to exit recovery (Y/n) ')" RecoveryDFU
    if [[ ${RecoveryDFU^} == N ]]; then
        Log "Exiting recovery mode."
        $irecovery -n
        exit
    fi
    Echo "* Hold POWER and HOME button for 8 seconds."
    for i in {08..01}; do
        echo -n "$i "
        sleep 1
    done
    echo -e "\n$(Echo '* Release POWER and hold HOME button for 8 seconds.')"
    for i in {08..01}; do
        echo -n "$i "
        sleep 1
    done
    FindDevice "DFU"
    [[ $DeviceState == "DFU" ]] && CheckM8
    Error "Failed to detect device in DFU mode. Please run the script again"
}

CheckM8() {
    local pwnDFUTool
    
    DFUManual=1
    [[ $platform == macos ]] && pwnDFUTool="iPwnder32" || pwnDFUTool="ipwndfu"
    Log "Entering pwnDFU mode with $pwnDFUTool..."
    if [[ $pwnDFUTool == "ipwndfu" ]]; then
        cd resources/ipwndfu
        sudo $python ipwndfu -p
    elif [[ $pwnDFUTool == "iPwnder32" ]]; then
        $ipwnder32 -p
        cd resources/ipwndfu
    fi
    if [[ $DeviceProc == 7 ]]; then
        Log "Running rmsigchks.py..."
        sudo $python rmsigchks.py
        pwnDFUDevice=$?
        Echo $pwnDFUDevice
        cd ../..
    else
        cd ../..
        [[ $pwnDFUTool == "ipwndfu" ]] && kDFU iBSS || echo
        pwnDFUDevice=$?
    fi
    
    if [[ $pwnDFUDevice == 1 ]] || [[ $pwnDFUDevice == 255 ]]; then
        echo -e "\n${Color_R}[Error] Failed to enter pwnDFU mode. Please run the script again: ./restore.sh Downgrade ${Color_N}"
        echo "${Color_Y}* This step may fail a lot, especially on Linux, and unfortunately there is nothing I can do about the low success rates. ${Color_N}"
        echo "${Color_Y}* The only option is to make sure you are using an Intel device, and to try multiple times ${Color_N}"
        exit 1
    elif [[ $pwnDFUDevice == 0 ]]; then
        Log "Device in pwnDFU mode detected."
    fi
}
