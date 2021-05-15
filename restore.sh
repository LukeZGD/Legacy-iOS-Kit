#!/bin/bash
trap 'Clean; exit' INT TERM EXIT
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
    
    if [[ $OSTYPE == "linux"* ]]; then
        . /etc/os-release 2>/dev/null
        platform="linux"
        ideviceenterrecovery="ideviceenterrecovery"
        ideviceinfo="ideviceinfo"
        idevicerestore="sudo LD_LIBRARY_PATH=resources/lib resources/tools/idevicerestore_linux"
        iproxy="iproxy"
        ipsw="env LD_LIBRARY_PATH=lib tools/ipsw_linux"
        irecoverychk="resources/libirecovery/bin/irecovery"
        irecovery="sudo LD_LIBRARY_PATH=resources/lib $irecoverychk"
        partialzip="resources/tools/partialzip_linux"
        python="python2"
        futurerestore1="sudo LD_PRELOAD=resources/lib/libcurl.so.3 LD_LIBRARY_PATH=resources/lib resources/tools/futurerestore1_linux"
        futurerestore2="sudo LD_LIBRARY_PATH=resources/lib resources/tools/futurerestore2_linux"
        tsschecker="env LD_LIBRARY_PATH=resources/lib resources/tools/tsschecker_linux"
        if [[ $UBUNTU_CODENAME == "bionic" ]] || [[ $VERSION == "10 (buster)" ]] ||
           [[ $PRETTY_NAME == "openSUSE Leap 15.2" ]]; then
            futurerestore2="${futurerestore2}_bionic"
            idevicerestore="${idevicerestore}_bionic"
        elif [[ $UBUNTU_CODENAME == "xenial" ]]; then
            futurerestore2="${futurerestore2}_xenial"
            idevicerestore="${idevicerestore}_xenial"
            partialzip="${partialzip}_xenial"
            tsschecker="${tsschecker}_xenial"
        fi

    elif [[ $OSTYPE == "darwin"* ]]; then
        macver=${1:-$(sw_vers -productVersion)}
        platform="macos"
        ideviceenterrecovery="resources/libimobiledevice/ideviceenterrecovery"
        ideviceinfo="resources/libimobiledevice/ideviceinfo"
        idevicerestore="resources/tools/idevicerestore_macos"
        iproxy="resources/libimobiledevice/iproxy"
        ipsw="tools/ipsw_macos"
        ipwnder32="resources/tools/ipwnder32_macos"
        irecovery="resources/libimobiledevice/irecovery"
        irecoverychk=$irecovery
        partialzip="resources/tools/partialzip_macos"
        python="python"
        futurerestore1="resources/tools/futurerestore1_macos"
        futurerestore2="resources/tools/futurerestore2_macos"
        tsschecker="resources/tools/tsschecker_macos"
    fi
    SSH="-F resources/ssh_config"
    SCP="scp $SSH"
    SSH="ssh $SSH"
    
    [[ ! -d resources ]] && Error "resources folder cannot be found. Replace resources folder and try again" "If resources folder is present try removing spaces from path/folder name"
    [[ ! $platform ]] && Error "Platform unknown/not supported."
    chmod +x resources/tools/*
    [ $? == 1 ] && Log "An error occurred in chmod. This might cause problems..."
    [[ ! $(ping -c1 8.8.8.8 2>/dev/null) ]] && Error "Please check your Internet connection before proceeding."
    if [[ $plaform == macos ]] && [[ $(uname -m) != 'x86_64' ]]; then
        Log "M1 Mac detected. Support is limited, the script may or may not work for you"
        Echo "* M1 macs can still proceed but I cannot support it if things break"
        Echo "* Proceed at your own risk."
        Input "Press Enter/Return to continue (or press Ctrl+C to cancel)"
        read -s
    elif [[ $(uname -m) != 'x86_64' ]]; then
        Error "Only x86_64 distributions are supported. Use a 64-bit distro and try again"
    fi
    
    if [[ $1 == Install ]] || [ ! $(which $irecoverychk) ] || [ ! $(which $ideviceinfo) ] ||
       [ ! $(which git) ] || [ ! $(which bspatch) ] || [ ! $(which $python) ]; then
        InstallDependencies
    fi
    
    SaveExternal iOS-OTA-Downgrader-Keys
    SaveExternal ipwndfu
    
    Log "Finding device in normal mode..."
    ideviceinfo2=$($ideviceinfo -s)
    if [[ $? != 0 ]]; then
        Log "Finding device in DFU/recovery mode..."
        irecovery2=$($irecovery -q 2>/dev/null | grep 'MODE' | cut -c 7-)
    fi
    [[ $irecovery2 == "DFU" ]] && DFUDevice=1
    [[ $irecovery2 == "Recovery" ]] && RecoveryDevice=1
    
    if [[ $DFUDevice == 1 ]] || [[ $RecoveryDevice == 1 ]]; then
        ProductType=$($irecovery -q | grep 'PTYP' | cut -c 7-)
        [ ! $ProductType ] && read -p "[Input] Enter ProductType (eg. iPad2,1): " ProductType
        UniqueChipID=$((16#$(echo $($irecovery -q | grep 'ECID' | cut -c 7-) | cut -c 3-)))
        ProductVer='Unknown'
        [[ $RecoveryDevice == 1 ]] && Echo "* Your $ProductType is currently in recovery mode. If you want to exit recovery, select Downgrade device, then select N to exit recovery"
    else
        ProductType=$(echo "$ideviceinfo2" | grep 'ProductType' | cut -c 14-)
        [ ! $ProductType ] && ProductType=$($ideviceinfo | grep 'ProductType' | cut -c 14-)
        ProductVer=$(echo "$ideviceinfo2" | grep 'ProductVer' | cut -c 17-)
        VersionDetect=$(echo $ProductVer | cut -c 1)
        UniqueChipID=$(echo "$ideviceinfo2" | grep 'UniqueChipID' | cut -c 15-)
        UniqueDeviceID=$(echo "$ideviceinfo2" | grep 'UniqueDeviceID' | cut -c 17-)
    fi
    [ ! $ProductType ] && ProductType=0
    BasebandDetect
    Clean
    mkdir tmp
    
    Echo "* Platform: $platform $macver"
    Echo "* HardwareModel: ${HWModel}ap"
    Echo "* ProductType: $ProductType"
    Echo "* ProductVersion: $ProductVer"
    Echo "* UniqueChipID (ECID): $UniqueChipID"
    echo
    
    if [[ $DFUDevice == 1 ]] && [[ $A7Device != 1 ]]; then
        DFUManual=1
        Mode='Downgrade'
        Log "32-bit device in DFU mode detected."
        Echo "* Advanced Options Menu"
        Input "This device is in:"
        select opt in "kDFU mode" "DFU mode (A6)" "pwnDFU mode (A5)" "(Any other key to exit)"; do
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
        SelectVersion
    elif [[ $RecoveryDevice == 1 ]] && [[ $A7Device != 1 ]]; then
        read -p "$(Input 'Is this an A6 device in recovery mode? (y/N) ')" DFUManual
        if [[ $DFUManual == y ]] || [[ $DFUManual == Y ]]; then
            Recovery
        else
            Error "32-bit device detected in recovery mode. Please put the device in normal mode and jailbroken before proceeding" "For usage of 32-bit ipwndfu, put the device in Recovery/DFU mode (A6) or pwnDFU mode (A5 using Arduino)"
        fi
    fi
    
    if [[ $1 ]] && [[ $1 != 'NoColor' ]]; then
        Mode="$1"
    else
        Selection=("Downgrade device")
        [[ $A7Device != 1 ]] && Selection+=("Save OTA blobs" "Just put device in kDFU mode")
        Selection+=("(Re-)Install Dependencies" "(Any other key to exit)")
        Echo "*** Main Menu ***"
        Input "Select an option:"
        select opt in "${Selection[@]}"; do
            case $opt in
                "Downgrade device" ) Mode='Downgrade'; break;;
                "Save OTA blobs" ) Mode='SaveOTABlobs'; break;;
                "Just put device in kDFU mode" ) Mode='kDFU'; break;;
                "(Re-)Install Dependencies" ) InstallDependencies;;
                * ) exit;;
            esac
        done
    fi
    SelectVersion
}

SelectVersion() {
    if [[ $ProductType == iPad4* ]] || [[ $ProductType == iPhone6* ]]; then
        OSVer='10.3.3'
        BuildVer='14G60'
        Action
    elif [[ $Mode == 'kDFU' ]]; then
        Action
    fi
    if [ $ProductType == iPhone5,3 ] || [ $ProductType == iPhone5,4 ]; then
        Selection=()
    else
        Selection=("iOS 8.4.1")
    fi
    if [ $ProductType == iPad2,1 ] || [ $ProductType == iPad2,2 ] ||
       [ $ProductType == iPad2,3 ] || [ $ProductType == iPhone4,1 ]; then
        Selection+=("iOS 6.1.3")
    fi
    [[ $Mode == 'Downgrade' ]] && Selection+=("Other (use SHSH blobs)")
    Selection+=("(Any other key to exit)")
    Input "Select iOS version:"
    select opt in "${Selection[@]}"; do
        case $opt in
            "iOS 8.4.1" ) OSVer='8.4.1'; BuildVer='12H321'; break;;
            "iOS 6.1.3" ) OSVer='6.1.3'; BuildVer='10B329'; break;;
            "Other (use SHSH blobs)" ) OSVer='Other'; break;;
            *) exit;;
        esac
    done
    Action
}

Action() {
    Log "Option: $Mode"
    if [[ $OSVer == 'Other' ]]; then
        Echo "* Move/copy the IPSW and SHSH to the directory where the script is located"
        Echo "* Remember to create a backup of the SHSH"
        read -p "$(Input 'Path to IPSW (drag IPSW to terminal window): ')" IPSW
        IPSW="$(basename $IPSW .ipsw)"
        read -p "$(Input 'Path to SHSH (drag SHSH to terminal window): ')" SHSH
        
    elif [[ $Mode == 'Downgrade' ]] && [[ $A7Device != 1 ]]; then
        read -p "$(Input 'Jailbreak the selected iOS version? (y/N): ')" Jailbreak
        [[ $Jailbreak == y ]] || [[ $Jailbreak == Y ]] && Jailbreak=1
        
    elif [[ $A7Device == 1 ]] && [[ $pwnDFUDevice != 0 ]]; then
        [[ $DFUDevice == 1 ]] && CheckM8 || Recovery
    fi
    
    if [[ $Mode == 'Downgrade' ]] && [[ $ProductType == iPhone5,1 ]] && [[ $Jailbreak != 1 ]]; then
        Echo "* By default, iOS-OTA-Downgrader now flashes the iOS 8.4.1 baseband to iPhone5,1"
        Echo "* Flashing the latest baseband is still available as an option but beware of problems it may cause"
        Echo "* There are potential network issues that with the latest baseband when used on iOS 8.4.1"
        read -p "$(Input 'Flash the latest baseband? (y/N) (press ENTER if unsure): ')" Baseband5
        if [[ $Baseband5 == y ]] || [[ $Baseband5 == Y ]]; then
            Baseband5=0
        else
            BasebandURL=$(cat $Firmware/12H321/url)
            Baseband=Mav5-8.02.00.Release.bbfw
            BasebandSHA1=db71823841ffab5bb41341576e7adaaeceddef1c
        fi
    fi
    
    [[ $Mode == 'Downgrade' ]] && Downgrade
    [[ $Mode == 'SaveOTABlobs' ]] && SaveOTABlobs
    [[ $Mode == 'kDFU' ]] && kDFU
    exit
}

SaveOTABlobs() {
    Log "Saving $OSVer blobs with tsschecker..."
    BuildManifest="resources/manifests/BuildManifest_${ProductType}_${OSVer}.plist"
    if [[ $A7Device == 1 ]]; then
        APNonce=$($irecovery -q | grep 'NONC' | cut -c 7-)
        Echo "* APNonce: $APNonce"
        $tsschecker -d $ProductType -B ${HWModel}ap -i $OSVer -e $UniqueChipID -m $BuildManifest --apnonce $APNonce -o -s
        SHSHChk=${UniqueChipID}_${ProductType}_${HWModel}ap_${OSVer}-${BuildVer}_${APNonce}.shsh*
    else
        $tsschecker -d $ProductType -i $OSVer -e $UniqueChipID -m $BuildManifest -o -s
        SHSHChk=${UniqueChipID}_${ProductType}_${OSVer}-${BuildVer}*.shsh*
    fi
    SHSH=$(ls $SHSHChk)
    SHSHExisting=$(ls saved/shsh/$SHSHChk 2>/dev/null)
    if [ ! $SHSH ] && [ ! $SHSHExisting ]; then
        Error "Saving $OSVer blobs failed. Please run the script again" "It is also possible that $OSVer for $ProductType is no longer signed"
    elif [ ! $SHSH ]; then
        Log "Saving $OSVer blobs failed, but detected existing saved SHSH blobs. Continuing..."
        cp $SHSHExisting .
        SHSH=$(ls $SHSHChk)
    else
        mkdir -p saved/shsh 2>/dev/null
        [[ ! $SHSHExisting ]] && cp "$SHSH" saved/shsh
        Log "Successfully saved $OSVer blobs."
    fi
}

kDFU() {
    if [ ! -e saved/$ProductType/$iBSS.dfu ]; then
        Log "Downloading iBSS..."
        $partialzip $(cat $Firmware/$iBSSBuildVer/url) Firmware/dfu/$iBSS.dfu $iBSS.dfu
        mkdir -p saved/$ProductType 2>/dev/null
        mv $iBSS.dfu saved/$ProductType
    fi
    [[ ! -e saved/$ProductType/$iBSS.dfu ]] && Error "Failed to save iBSS. Please run the script again"
    Log "Patching iBSS..."
    bspatch saved/$ProductType/$iBSS.dfu tmp/pwnediBSS resources/patches/$iBSS.patch
    
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
    Log "Finding device in DFU mode..."
    while [[ $DFUDevice != 1 ]]; do
        [[ $platform == linux ]] && DFUDevice=$(lsusb | grep -c '1227')
        [[ $platform == macos ]] && [[ $($irecovery -q 2>/dev/null | grep 'MODE' | cut -c 7-) == "DFU" ]] && DFUDevice=1
        sleep 1
    done
    Log "Found device in DFU mode."
    kill $iproxyPID
}

Recovery() {
    [[ $($irecovery -q 2>/dev/null | grep 'MODE' | cut -c 7-) == "Recovery" ]] && RecoveryDevice=1
    if [[ $RecoveryDevice != 1 ]]; then
        Log "Entering recovery mode..."
        $ideviceenterrecovery $UniqueDeviceID >/dev/null
        while [[ $RecoveryDevice != 1 ]]; do
            [[ $($irecovery -q 2>/dev/null | grep 'MODE' | cut -c 7-) == "Recovery" ]] && RecoveryDevice=1
        done
    fi
    Log "Device in recovery mode detected. Get ready to enter DFU mode"
    read -p "$(Input 'Select Y to continue, N to exit recovery (Y/n) ')" RecoveryDFU
    if [[ $RecoveryDFU == n ]] || [[ $RecoveryDFU == N ]]; then
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
    sleep 2
    [[ $($irecovery -q 2>/dev/null | grep 'MODE' | cut -c 7-) == "DFU" ]] && DFUDevice=1
    [[ $DFUDevice == 1 ]] && CheckM8
    Error "Failed to detect device in DFU mode. Please run the script again"
}

CheckM8() {
    DFUManual=1
    [[ $A7Device == 1 ]] && echo -e "\n$(Log 'Device in DFU mode detected.')"
    if [[ $platform == macos ]]; then
        Selection=("iPwnder32" "ipwndfu")
        Input "Select pwnDFU tool to use (Select 1 if unsure):"
        select opt in "${Selection[@]}"; do
            case $opt in
                "ipwndfu" ) pwnDFUTool="ipwndfu"; break;;
                *) pwnDFUTool="iPwnder32"; break;;
            esac
        done
    else
        pwnDFUTool="ipwndfu"
    fi
    Log "Entering pwnDFU mode with $pwnDFUTool..."
    if [[ $pwnDFUTool == "ipwndfu" ]]; then
        cd resources/ipwndfu
        sudo $python ipwndfu -p
    elif [[ $pwnDFUTool == "iPwnder32" ]]; then
        if [ ! -e $ipwnder32 ]; then
            SaveFile https://dora2ios.web.app/iPwnder32/iPwnder32_v3.1.2.zip tmp/iPwnder32.zip 79a64133e11b1c60569aba422fa1b5046aa33d83
            unzip -o -j tmp/iPwnder32.zip iPwnder32_macosx/iPwnder32 -d resources/tools
            mv resources/tools/iPwnder32 $ipwnder32
        fi
        $ipwnder32 -p
        cd resources/ipwndfu
    fi
    if [[ $A7Device == 1 ]]; then
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
        Log "Downgrading device $ProductType in pwnDFU mode..."
        Mode='Downgrade'
        SelectVersion
    fi    
}

Downgrade() {    
    if [[ $OSVer != 'Other' ]]; then
        [[ $ProductType == iPad4* ]] && IPSWType="iPad_64bit"
        [[ $ProductType == iPhone6* ]] && IPSWType="iPhone_4.0_64bit"
        [[ ! $IPSWType ]] && IPSWType="$ProductType" && SaveOTABlobs
        IPSW="${IPSWType}_${OSVer}_${BuildVer}_Restore"
        IPSWCustom="${IPSWType}_${OSVer}_${BuildVer}_Custom"
        if [ ! -e $IPSW.ipsw ] && [ ! -e $IPSWCustom.ipsw ]; then
            Log "iOS $OSVer IPSW cannot be found."
            Echo "* If you already downloaded the IPSW, did you put it in the same directory as the script?"
            Echo "* Do NOT rename the IPSW as the script will fail to detect it"
            Log "Downloading IPSW... (Press Ctrl+C to cancel)"
            curl -L $(cat $Firmware/$BuildVer/url) -o tmp/$IPSW.ipsw
            mv tmp/$IPSW.ipsw .
        fi
        [[ $Jailbreak == 1 ]] && [ -e $IPSWCustom.ipsw ] && Verify=0
        if [[ $Verify != 0 ]]; then
            Log "Verifying IPSW..."
            IPSWSHA1=$(cat $Firmware/$BuildVer/sha1sum)
            IPSWSHA1L=$(shasum $IPSW.ipsw | awk '{print $1}')
            [[ $IPSWSHA1L != $IPSWSHA1 ]] && Error "Verifying IPSW failed. Your IPSW may be corrupted or incomplete." "Delete/replace the IPSW and run the script again"
        else
            IPSW=$IPSWCustom
        fi
        if [ ! $DFUManual ] && [[ $iBSSBuildVer == $BuildVer ]]; then
            Log "Extracting iBSS from IPSW..."
            mkdir -p saved/$ProductType 2>/dev/null
            unzip -o -j $IPSW.ipsw Firmware/dfu/$iBSS.dfu -d saved/$ProductType
        fi
    fi
    
    [ ! $DFUManual ] && kDFU
    
    # uses ipsw tool from OdysseusOTA/2 to create custom IPSW with jailbreak
    if [[ $Jailbreak == 1 ]]; then
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
        if [ ! -e $IPSWCustom.ipsw ]; then
            Echo "* By default, memory option is set to Y, you may select N later if you encounter problems"
            Echo "* If it doesn't work with both, you might not have enough RAM and/or tmp storage"
            read -p "$(Input 'Memory option? (press ENTER if unsure) (Y/n): ')" JBMemory
            [[ $JBMemory != n ]] && [[ $JBMemory != N ]] && JBMemory="-memory" || JBMemory=
            Log "Preparing custom IPSW..."
            cd resources
            ln -sf firmware/FirmwareBundles FirmwareBundles
            $ipsw ../$IPSW.ipsw ../$IPSWCustom.ipsw $JBMemory -bbupdate -s $JBS ${JBFiles[@]}
            cd ..
        fi
        [ ! -e $IPSWCustom.ipsw ] && Error "Failed to find custom IPSW. Please run the script again" "You may try selecting N for memory option"
        IPSW=$IPSWCustom
    fi
    
    Log "Extracting IPSW..."
    unzip -q $IPSW.ipsw -d $IPSW/
    
    # create custom IPSW for 10.3.3
    if [[ $A7Device == 1 ]]; then
        if [ ! -e $IPSWCustom.ipsw ]; then
            Log "Preparing custom IPSW..."
            cp $IPSW/Firmware/all_flash/$SEP .
            bspatch $IPSW/Firmware/dfu/$iBSS.im4p $iBSS.im4p resources/patches/$iBSS.patch
            bspatch $IPSW/Firmware/dfu/$iBEC.im4p $iBEC.im4p resources/patches/$iBEC.patch
            if [[ $ProductType == iPad4* ]]; then
                bspatch $IPSW/Firmware/dfu/$iBSSb.im4p $iBSSb.im4p resources/patches/$iBSSb.patch
                bspatch $IPSW/Firmware/dfu/$iBECb.im4p $iBECb.im4p resources/patches/$iBECb.patch
                cp -f $iBSSb.im4p $iBECb.im4p $IPSW/Firmware/dfu
            fi
            cp -f $iBSS.im4p $iBEC.im4p $IPSW/Firmware/dfu
            cd $IPSW
            zip ../$IPSWCustom.ipsw -rq0 *
            cd ..
            mv $IPSW $IPSWCustom
            IPSW=$IPSWCustom
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
    fi
    
    if [[ $Jailbreak != 1 ]] && [[ $A7Device != 1 ]] && [[ $OSVer != 'Other' ]]; then
        Log "Preparing for futurerestore... (Enter root password of your PC/Mac when prompted)"
        cd resources
        sudo bash -c "$python -m SimpleHTTPServer 80 &"
        cd ..
    fi
    
    if [[ $Jailbreak == 1 ]]; then
        Log "Proceeding to idevicerestore... (Enter root password of your PC/Mac when prompted)"
        [[ $platform == macos ]] && sudo codesign --sign - --force --deep $idevicerestore
        mkdir shsh
        mv $SHSH shsh/${UniqueChipID}-${ProductType}-${OSVer}.shsh
        $idevicerestore -y -e -w $IPSW.ipsw
    elif [ $Baseband == 0 ]; then
        Log "Device $ProductType has no baseband"
        Log "Proceeding to futurerestore..."
        if [[ $A7Device == 1 ]]; then
            $futurerestore2 -t $SHSH -s $SEP -m $BuildManifest --no-baseband $IPSW.ipsw
        else
            $futurerestore1 -t $SHSH --no-baseband --use-pwndfu $IPSW.ipsw
        fi
    else
        if [[ $A7Device == 1 ]]; then
            cp $IPSW/Firmware/$Baseband .
        elif [ $ProductType == iPhone5,1 ] && [[ $Baseband5 != 0 ]]; then
            unzip -o -j $IPSW.ipsw Firmware/$Baseband -d .
            cp $BuildManifest BuildManifest.plist
        elif [ ! -e saved/baseband/$Baseband ]; then
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
        BasebandSHA1L=$(shasum $Baseband | awk '{print $1}')
        Log "Proceeding to futurerestore..."
        if [ ! -e *.bbfw ] || [[ $BasebandSHA1L != $BasebandSHA1 ]]; then
            rm -f saved/$ProductType/*.bbfw saved/$ProductType/BuildManifest.plist
            Log "Downloading/verifying baseband failed."
            Echo "* Your device is still in kDFU mode and you may run the script again"
            Echo "* You can also continue and futurerestore can attempt to download the baseband again"
            Input "Press Enter/Return to continue (or press Ctrl+C to cancel)"
            read -s
            $futurerestore1 -t $SHSH --latest-baseband --use-pwndfu $IPSW.ipsw
        elif [[ $A7Device == 1 ]]; then
            $futurerestore2 -t $SHSH -s $SEP -m $BuildManifest -b $Baseband -p $BuildManifest $IPSW.ipsw
        else
            $futurerestore1 -t $SHSH -b $Baseband -p BuildManifest.plist --use-pwndfu $IPSW.ipsw
        fi
    fi
    
    echo
    Log "Restoring done!"
    if [[ $Jailbreak != 1 ]] && [[ $A7Device != 1 ]] && [[ $OSVer != 'Other' ]]; then
        Log "Stopping local server... (Enter root password of your PC/Mac when prompted)"
        ps aux | awk '/python/ {print "sudo kill -9 "$2" 2>/dev/null"}' | bash
    fi
    Log "Downgrade script done!"
}

InstallDependencies() {
    mkdir tmp 2>/dev/null
    cd resources
    rm -rf firmware ipwndfu lib/* libimobiledevice* libirecovery
    cd ../tmp
    
    Log "Installing dependencies..."
    if [[ $ID == "arch" ]] || [[ $ID_LIKE == "arch" ]]; then
        # Arch
        sudo pacman -Syu --noconfirm --needed base-devel bsdiff curl libcurl-compat libpng12 libimobiledevice libusbmuxd libzip openssh openssl-1.0 python2 unzip usbmuxd usbutils
        ln -sf /usr/lib/libcurl.so.3 ../resources/lib/libcurl.so.3
        ln -sf /usr/lib/libzip.so.5 ../resources/lib/libzip.so.4
    
    elif [[ $UBUNTU_CODENAME == "bionic" ]] || [[ $UBUNTU_CODENAME == "focal" ]] ||
         [[ $UBUNTU_CODENAME == "groovy" ]] || [[ $UBUNTU_CODENAME == "hirsute" ]] ||
         [[ $VERSION == "10 (buster)" ]] || [[ $PRETTY_NAME == "Debian GNU/Linux bullseye/sid" ]]; then
        # Ubuntu, Debian
        [[ ! -z $UBUNTU_CODENAME ]] && sudo add-apt-repository universe
        sudo apt update
        sudo apt install -y autoconf automake bsdiff build-essential curl git libglib2.0-dev libimobiledevice6 libimobiledevice-utils libreadline-dev libtool-bin libusb-1.0-0-dev libusbmuxd-tools openssh-client usbmuxd usbutils
        SavePkg
        cp libcrypto.so.1.0.0 libcurl.so.3 libssl.so.1.0.0 ../resources/lib
        if [[ $UBUNTU_CODENAME == "bionic" ]] || [[ $VERSION == "10 (buster)" ]]; then
            sudo apt install -y libzip4 python
            cp libpng12.so.0 libzip.so.5 ../resources/lib
            SaveFile https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/tools_linux_bionic.zip tools_linux_bionic.zip 959abbafacfdaddf87dd07683127da1dab6c835f
            unzip tools_linux_bionic.zip -d ../resources/tools
        elif [[ $PRETTY_NAME == "Debian GNU/Linux bullseye/sid" ]] || [[ $UBUNTU_CODENAME == "hirsute" ]]; then
            sudo apt install -y libzip4 python2
            cp libpng12.so.0 libzip.so.5 ../resources/lib
        else
            sudo apt install -y libzip5 python2
            cp libpng12.so.0 libzip.so.4 ../resources/lib
        fi
        if [[ $UBUNTU_CODENAME == "focal" ]]; then
            ln -sf /usr/lib/x86_64-linux-gnu/libimobiledevice.so.6 ../resources/lib/libimobiledevice-1.0.so.6
            ln -sf /usr/lib/x86_64-linux-gnu/libplist.so.3 ../resources/lib/libplist-2.0.so.3
            ln -sf /usr/lib/x86_64-linux-gnu/libusbmuxd.so.6 ../resources/lib/libusbmuxd-2.0.so.6
        fi
    
    elif [[ $ID == "fedora" ]]; then
        # Fedora
        sudo dnf install -y automake binutils bsdiff git libimobiledevice-utils libpng12 libtool libusb-devel libusbmuxd-utils make libzip perl-Digest-SHA python2 readline-devel
        SavePkg
        cp libcrypto.so.1.0.0 libssl.so.1.0.0 ../resources/lib
        if (( $VERSION_ID <= 32 )); then
            ln -sf /usr/lib64/libimobiledevice.so.6 ../resources/lib/libimobiledevice-1.0.so.6
            ln -sf /usr/lib64/libplist.so.3 ../resources/lib/libplist-2.0.so.3
            ln -sf /usr/lib64/libusbmuxd.so.6 ../resources/lib/libusbmuxd-2.0.so.6
        fi
        ln -sf /usr/lib64/libzip.so.5 ../resources/lib/libzip.so.4
        ln -sf /usr/lib64/libbz2.so.1.* ../resources/lib/libbz2.so.1.0
    
    elif [[ $ID == "opensuse-tumbleweed" ]] || [[ $PRETTY_NAME == "openSUSE Leap 15.2" ]]; then
        # openSUSE
        [[ $ID == "opensuse-tumbleweed" ]] && iproxy="libusbmuxd-tools" || iproxy="iproxy libzip5"
        sudo zypper -n in automake bsdiff gcc git imobiledevice-tools $iproxy libimobiledevice libpng12-0 libopenssl1_0_0 libusb-1_0-devel libtool make python-base readline-devel
        ln -sf /usr/lib64/libimobiledevice.so.6 ../resources/lib/libimobiledevice-1.0.so.6
        ln -sf /usr/lib64/libplist.so.3 ../resources/lib/libplist-2.0.so.3
        ln -sf /usr/lib64/libusbmuxd.so.6 ../resources/lib/libusbmuxd-2.0.so.6
        ln -sf /usr/lib64/libzip.so.5 ../resources/lib/libzip.so.4
    
    elif [[ $OSTYPE == "darwin"* ]]; then
        # macOS
        #imobiledevicenet=$(curl -s https://api.github.com/repos/libimobiledevice-win32/imobiledevice-net/releases/latest | grep browser_download_url | cut -d '"' -f 4 | awk '/osx-x64/ {print $1}')
        xcode-select --install
        #curl -L $imobiledevicenet -o libimobiledevice.zip
        SaveFile https://github.com/libimobiledevice-win32/imobiledevice-net/releases/download/v1.3.14/libimobiledevice.1.2.1-r1116-osx-x64.zip libimobiledevice.zip 328e809dea350ae68fb644225bbf8469c0f0634b
        
    else
        Error "Distro not detected/supported by the install script." "See the repo README for supported OS versions/distros"
    fi
    
    if [[ $platform == linux ]]; then
        Compile LukeZGD libirecovery
        ln -sf ../libirecovery/lib/libirecovery.so.3 ../resources/lib/libirecovery-1.0.so.3
        ln -sf ../libirecovery/lib/libirecovery.so.3 ../resources/lib/libirecovery.so.3
    else
        mkdir ../resources/libimobiledevice
        unzip libimobiledevice.zip -d ../resources/libimobiledevice
        chmod +x ../resources/libimobiledevice/*
    fi
    
    Log "Install script done! Please run the script again to proceed"
    exit
}

Compile() {
    git clone --depth 1 https://github.com/$1/$2.git
    cd $2
    ./autogen.sh --prefix="$(cd ../.. && pwd)/resources/$2"
    make install
    cd ..
    sudo rm -rf $2
}

SaveExternal() {
    ExternalURL="https://github.com/LukeZGD/$1.git"
    External=$1
    [[ $1 == "iOS-OTA-Downgrader-Keys" ]] && External="firmware"
    cd resources
    if [[ ! -d $External ]] || [[ ! -d $External/.git ]]; then
        Log "Downloading $External..."
        rm -rf $External
        git clone $ExternalURL $External
    #else
    #    Log "Updating $External..."
    #    cd $External
    #    git pull 2>/dev/null
    #    cd ..
    fi
    if [[ ! -e $External/README.md ]] || [[ ! -d $External/.git ]]; then
        rm -rf $External
        Error "Downloading/updating $1 failed. Please run the script again"
    fi
    cd ..
}

SaveFile() {
    curl -L $1 -o $2
    if [[ $(shasum $2 | awk '{print $1}') != $3 ]]; then
        Error "Verifying failed. Please run the script again" "./restore.sh Install"
    fi
}

SavePkg() {
    if [[ ! -d ../saved/lib ]]; then
        Log "Downloading packages..."
        SaveFile https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/depends2_linux.zip depends_linux.zip 38cf1db21c9aba88f0de95a1a7959ac2ac53c464
        mkdir -p ../saved/lib
        unzip depends_linux.zip -d ../saved/lib
    fi
    cp ../saved/lib/* .
}

BasebandDetect() {
    Firmware=resources/firmware/$ProductType
    BasebandURL=$(cat $Firmware/13G37/url 2>/dev/null) # iOS 9.3.6
    Baseband=0
    if [ $ProductType == iPad2,2 ]; then
        BasebandURL=$(cat $Firmware/13G36/url) # iOS 9.3.5
        Baseband=ICE3_04.12.09_BOOT_02.13.Release.bbfw
        BasebandSHA1=e6f54acc5d5652d39a0ef9af5589681df39e0aca
    elif [ $ProductType == iPad2,3 ]; then
        Baseband=Phoenix-3.6.03.Release.bbfw
        BasebandSHA1=8d4efb2214344ea8e7c9305392068ab0a7168ba4
    elif [ $ProductType == iPad2,6 ] || [ $ProductType == iPad2,7 ]; then
        Baseband=Mav5-11.80.00.Release.bbfw
        BasebandSHA1=aa52cf75b82fc686f94772e216008345b6a2a750
    elif [ $ProductType == iPad3,2 ] || [ $ProductType == iPad3,3 ]; then
        Baseband=Mav4-6.7.00.Release.bbfw
        BasebandSHA1=a5d6978ecead8d9c056250ad4622db4d6c71d15e
    elif [ $ProductType == iPhone4,1 ]; then
        Baseband=Trek-6.7.00.Release.bbfw
        BasebandSHA1=22a35425a3cdf8fa1458b5116cfb199448eecf49
    elif [ $ProductType == iPad3,5 ] || [ $ProductType == iPad3,6 ] ||
         [ $ProductType == iPhone5,1 ] || [ $ProductType == iPhone5,2 ]; then
        BasebandURL=$(cat $Firmware/14G61/url) # iOS 10.3.4
        Baseband=Mav5-11.80.00.Release.bbfw
        BasebandSHA1=8951cf09f16029c5c0533e951eb4c06609d0ba7f
    elif [ $ProductType == iPad4,2 ] || [ $ProductType == iPad4,3 ] || [ $ProductType == iPad4,5 ] ||
         [ $ProductType == iPhone6,1 ] || [ $ProductType == iPhone6,2 ]; then
        BasebandURL=$(cat $Firmware/14G60/url)
        Baseband=Mav7Mav8-7.60.00.Release.bbfw
        BasebandSHA1=f397724367f6bed459cf8f3d523553c13e8ae12c
        A7Device=1
    elif [ $ProductType == iPad4,1 ] || [ $ProductType == iPad4,4 ]; then
        A7Device=1
    elif [ $ProductType == 0 ]; then
        Error "No device detected. Please put the device in normal mode (and jailbroken for 32-bit) before proceeding" "Recovery or DFU mode is also applicable for A7 devices"
    elif [ $ProductType != iPad2,1 ] && [ $ProductType != iPad2,4 ] && [ $ProductType != iPad2,5 ] &&
         [ $ProductType != iPad3,1 ] && [ $ProductType != iPad3,4 ] && [ $ProductType != iPod5,1 ] &&
         [ $ProductType != iPhone5,3 ] && [ $ProductType != iPhone5,4 ]; then
        Error "Your device $ProductType is not supported."
    fi
    
    [ $ProductType == iPad2,1 ] && HWModel=k93
    [ $ProductType == iPad2,2 ] && HWModel=k94
    [ $ProductType == iPad2,3 ] && HWModel=k95
    [ $ProductType == iPad2,4 ] && HWModel=k93a
    [ $ProductType == iPad2,5 ] && HWModel=p105
    [ $ProductType == iPad2,6 ] && HWModel=p106
    [ $ProductType == iPad2,7 ] && HWModel=p107
    [ $ProductType == iPad3,1 ] && HWModel=j1
    [ $ProductType == iPad3,2 ] && HWModel=j2
    [ $ProductType == iPad3,3 ] && HWModel=j2a
    [ $ProductType == iPad3,4 ] && HWModel=p101
    [ $ProductType == iPad3,5 ] && HWModel=p102
    [ $ProductType == iPad3,6 ] && HWModel=p103
    [ $ProductType == iPad4,1 ] && HWModel=j71
    [ $ProductType == iPad4,2 ] && HWModel=j72
    [ $ProductType == iPad4,3 ] && HWModel=j73
    [ $ProductType == iPad4,4 ] && HWModel=j85
    [ $ProductType == iPad4,5 ] && HWModel=j86
    [ $ProductType == iPhone4,1 ] && HWModel=n94
    [ $ProductType == iPhone5,1 ] && HWModel=n41
    [ $ProductType == iPhone5,2 ] && HWModel=n42
    [ $ProductType == iPhone5,3 ] && HWModel=n48
    [ $ProductType == iPhone5,4 ] && HWModel=n49
    [ $ProductType == iPhone6,1 ] && HWModel=n51
    [ $ProductType == iPhone6,2 ] && HWModel=n53
    [ $ProductType == iPod5,1 ] && HWModel=n78
    
    if [ $ProductType == iPod5,1 ]; then
        iBSS="${HWModel}ap"
        iBSSBuildVer='10B329'
    elif [ $ProductType == iPad3,1 ]; then
        iBSS="${HWModel}ap"
        iBSSBuildVer='11D257'
    elif [ $ProductType == iPhone6,1 ] || [ $ProductType == iPhone6,2 ]; then
        iBSS="iphone6"
    elif [ $ProductType == iPad4,1 ] || [ $ProductType == iPad4,2 ] || [ $ProductType == iPad4,3 ] ||
         [ $ProductType == iPad4,4 ] || [ $ProductType == iPad4,5 ]; then
        iBSS="ipad4"
    else
        iBSS="$HWModel"
        iBSSBuildVer='12H321'
    fi
    iBEC="iBEC.$iBSS.RELEASE"
    iBECb="iBEC.${iBSS}b.RELEASE"
    iBSSb="iBSS.${iBSS}b.RELEASE"
    iBSS="iBSS.$iBSS.RELEASE"
    SEP="sep-firmware.$HWModel.RELEASE.im4p"
}

cd "$(dirname $0)"
Main $1
