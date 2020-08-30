#!/bin/bash
trap 'Clean; exit' INT TERM EXIT

function Clean {
    rm -rf iP*/ tmp/ ${UniqueChipID}_${ProductType}_${OSVer}-*.shsh2 ${UniqueChipID}_${ProductType}_${HWModel}ap_${OSVer}-*.shsh *.im4p *.bbfw BuildManifest.plist
}

function Error {
    echo -e "\n[Error] $1"
    [[ ! -z $2 ]] && echo "* $2"
    echo
    exit
}

function Log {
    echo "[Log] $1"
}

function Main {
    clear
    echo "******* iOS-OTA-Downgrader *******"
    echo "   Downgrader script by LukeZGD   "
    echo
    
    if [[ $OSTYPE == "linux-gnu" ]]; then
        platform='linux'
        bspatch="bspatch"
        ideviceenterrecovery="ideviceenterrecovery"
        ideviceinfo="ideviceinfo"
        igetnonce="sudo LD_LIBRARY_PATH=resources/lib resources/tools/igetnonce_linux"
        iproxy="iproxy"
        irecovery="sudo LD_LIBRARY_PATH=/usr/local/lib irecovery"
        lsusb="lsusb"
        python="python2"
        futurerestore1="sudo LD_PRELOAD=resources/lib/libcurl.so.3 LD_LIBRARY_PATH=resources/lib resources/tools/futurerestore1_linux"
        futurerestore2="sudo LD_LIBRARY_PATH=resources/lib resources/tools/futurerestore2_linux"
        tsschecker="env LD_LIBRARY_PATH=resources/lib resources/tools/tsschecker_linux"
        if [[ $UBUNTU_CODENAME == "bionic" ]]; then
            futurerestore2="${futurerestore2}_bionic"
            tsschecker="${tsschecker}_bionic"
        fi
    else
        if [[ $OSTYPE == "darwin"* ]]; then
            platform='macos'
            lsusb="system_profiler SPUSBDataType 2>/dev/null"
        elif [[ $(uname -s) == "MINGW64_NT"* ]]; then
            platform='win'
            lsusb="wmic path Win32_USBControllerDevice get Dependent"
            ping="ping -n 1"
        fi
        bspatch="resources/tools/bspatch_$platform"
        ideviceenterrecovery="resources/libimobiledevice_$platform/ideviceenterrecovery"
        ideviceinfo="resources/libimobiledevice_$platform/ideviceinfo"
        igetnonce="resources/tools/igetnonce_$platform"
        iproxy="resources/libimobiledevice_$platform/iproxy"
        irecovery="resources/libimobiledevice_$platform/irecovery"
        python="python"
        futurerestore1="resources/tools/futurerestore1_$platform"
        futurerestore2="resources/tools/futurerestore2_$platform"
        tsschecker="resources/tools/tsschecker_$platform"
    fi
    partialzip="resources/tools/partialzip_$platform"
    [[ ! $ping ]] && ping="ping -c1"
    
    [[ ! $platform ]] && Error "Platform unknown/not supported."
    [[ ! $($ping google.com 2>/dev/null) ]] && Error "Please check your Internet connection before proceeding."
    [[ $(uname -m) != 'x86_64' ]] && Error "Only x86_64 distributions are supported. Use a 64-bit distro and try again"
    
    DFUDevice=$($lsusb | grep -ci '1227')
    RecoveryDevice=$($lsusb | grep -ci '1281')
    if [[ $1 == Install ]] || [ ! $(which $bspatch) ] || [ ! $(which $ideviceinfo) ] ||
       [ ! $(which git) ] || [ ! $(which ssh) ] || [ ! $(which $python) ]; then
        InstallDependencies
    elif [ $DFUDevice == 1 ] || [ $RecoveryDevice == 1 ]; then
        ProductType=$($igetnonce 2>/dev/null)
        [ ! $ProductType ] && read -p "[Input] Enter ProductType (eg. iPad2,1): " ProductType
        UniqueChipID=$((16#$(echo $($irecovery -q | grep 'ECID' | cut -c 7-) | cut -c 3-)))
        ProductVer='Unknown'
    else
        ideviceinfo2=$($ideviceinfo -s)
        ProductType=$(echo "$ideviceinfo2" | grep 'ProductType' | cut -c 14-)
        [ ! $ProductType ] && ProductType=$($ideviceinfo | grep 'ProductType' | cut -c 14-)
        ProductVer=$(echo "$ideviceinfo2" | grep 'ProductVer' | cut -c 17-)
        VersionDetect=$(echo $ProductVer | cut -c 1)
        UniqueChipID=$(echo "$ideviceinfo2" | grep 'UniqueChipID' | cut -c 15-)
        UniqueDeviceID=$(echo "$ideviceinfo2" | grep 'UniqueDeviceID' | cut -c 17-)
    fi
    [ ! $ProductType ] && ProductType=0
    SaveExternal iOS-OTA-Downgrader-Keys
    SaveExternal ipwndfu
    BasebandDetect
    Clean
    mkdir tmp
    chmod +x resources/tools/*
    
    echo "* Platform: $platform"
    echo "* HardwareModel: ${HWModel}ap"
    echo "* ProductType: $ProductType"
    echo "* ProductVersion: $ProductVer"
    echo "* UniqueChipID (ECID): $UniqueChipID"
    echo
    
    if [[ $DFUDevice == 1 ]] && [[ $A7Device != 1 ]] && [[ $platform != win ]]; then
        DFUManual=1
        Mode='Downgrade'
        Log "32-bit device in DFU mode detected."
        echo "* Advanced options menu - use at your own risk"
        echo "* Warning: A6 devices won't have activation error workaround yet when using this method"
        echo "[Input] This device is in:"
        select opt in "kDFU mode" "DFU mode (ipwndfu A6)" "pwnDFU mode (checkm8 A5)" "(Any other key to exit)"; do
            case $opt in
                "kDFU mode" ) break;;
                "DFU mode (ipwndfu A6)" ) CheckM8; break;;
                "pwnDFU mode (checkm8 A5)" ) kDFU iBSS; break;;
                * ) exit;;
            esac
        done
        Log "Downgrading $ProductType in kDFU/pwnDFU mode..."
        SelectVersion
    elif [[ $RecoveryDevice == 1 ]] && [[ $A7Device != 1 ]]; then
        Error "32-bit device detected in recovery mode. Please put the device in normal mode and jailbroken before proceeding" "For usage of 32-bit ipwndfu, put the device in DFU mode (A6) or pwnDFU mode (A5 using Arduino)"
    fi
    
    if [[ $1 ]]; then
        Mode="$1"
    else
        Selection=("Downgrade device")
        [[ $A7Device != 1 ]] && Selection+=("Save OTA blobs" "Just put device in kDFU mode")
        Selection+=("(Re-)Install Dependencies" "(Any other key to exit)")
        echo "*** Main Menu ***"
        echo "[Input] Select an option:"
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

function SelectVersion {
    if [[ $ProductType == iPad4* ]] || [[ $ProductType == iPhone6* ]]; then
        OSVer='10.3.3'
        BuildVer='14G60'
        Action
    elif [[ $Mode == 'kDFU' ]]; then
        Action
    fi
    Selection=("iOS 8.4.1")
    if [ $ProductType == iPad2,1 ] || [ $ProductType == iPad2,2 ] ||
       [ $ProductType == iPad2,3 ] || [ $ProductType == iPhone4,1 ]; then
        Selection+=("iOS 6.1.3")
    fi
    [[ $Mode == 'Downgrade' ]] && Selection+=("Other")
    Selection+=("(Any other key to exit)")
    echo "[Input] Select iOS version:"
    select opt in "${Selection[@]}"; do
        case $opt in
            "iOS 8.4.1" ) OSVer='8.4.1'; BuildVer='12H321'; break;;
            "iOS 6.1.3" ) OSVer='6.1.3'; BuildVer='10B329'; break;;
            "Other" ) OSVer='Other'; break;;
            *) exit;;
        esac
    done
    Action
}

function Action {    
    Log "Option: $Mode"
    if [[ $OSVer == 'Other' ]]; then
        echo "* Move/copy the IPSW and SHSH to the directory where the script is located"
        echo "* Reminder to create a backup of the SHSH"
        read -p "[Input] Path to IPSW (drag IPSW to terminal window): " IPSW
        IPSW="$(basename $IPSW .ipsw)"
        read -p "[Input] Path to SHSH (drag SHSH to terminal window): " SHSH
    elif [[ $A7Device == 1 ]] && [[ $pwnDFUDevice != 1 ]]; then
        [[ $DFUDevice == 1 ]] && CheckM8 || Recovery
    fi

    [[ $Mode == 'Downgrade' ]] && Downgrade
    [[ $Mode == 'SaveOTABlobs' ]] && SaveOTABlobs
    [[ $Mode == 'kDFU' ]] && kDFU
    exit
}

function SaveOTABlobs {
    Log "Saving $OSVer blobs with tsschecker..."
    BuildManifest="resources/manifests/BuildManifest_${ProductType}_${OSVer}.plist"
    if [[ $A7Device == 1 ]]; then
        APNonce=$($irecovery -q | grep 'NONC' | cut -c 7-)
        echo "* APNonce: $APNonce"
        $tsschecker -d $ProductType -B ${HWModel}ap -i $OSVer -e $UniqueChipID -m $BuildManifest --apnonce $APNonce -o -s
        SHSH=$(ls ${UniqueChipID}_${ProductType}_${HWModel}ap_${OSVer}-${BuildVer}_${APNonce}.shsh)
    else
        $tsschecker -d $ProductType -i $OSVer -e $UniqueChipID -m $BuildManifest -o -s
        SHSH=$(ls ${UniqueChipID}_${ProductType}_${OSVer}-${BuildVer}_*.shsh2)
    fi
    [ ! $SHSH ] && Error "Saving $OSVer blobs failed. Please run the script again" "It is also possible that $OSVer for $ProductType is no longer signed"
    mkdir -p saved/shsh 2>/dev/null
    cp "$SHSH" saved/shsh
    Log "Successfully saved $OSVer blobs."
}

function kDFU {
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
        cd resources/ipwndfu 2>/dev/null
        Log "Booting iBSS..."
        sudo $python ipwndfu -l ../../tmp/pwnediBSS
        cd ../..
        return $?
    fi
    
    [[ $VersionDetect == 1 ]] && kloader='kloader_hgsp'
    [[ $VersionDetect == 5 ]] && kloader='kloader5'
    [[ ! $kloader ]] && kloader='kloader'
    
    [ ! $(which $iproxy) ] && Error "iproxy cannot be found. Please re-install dependencies and try again" "./restore.sh Install"
    $iproxy 2222 22 &
    iproxyPID=$!
    WifiAddr=$(echo "$ideviceinfo2" | grep 'WiFiAddress' | cut -c 14-)
    WifiAddrDecr=$(echo $(printf "%x\n" $(expr $(printf "%d\n" 0x$(echo "${WifiAddr}" | tr -d ':')) - 1)) | sed 's/\(..\)/\1:/g;s/:$//')
    echo '#!/bin/bash' > tmp/pwn.sh
    echo "nvram wifiaddr=$WifiAddrDecr" >> tmp/pwn.sh
    chmod +x tmp/pwn.sh
    
    echo "* Make sure OpenSSH/Dropbear is installed on the device!"
    Log "Copying stuff to device via SSH..."
    echo "* (Enter root password of your iOS device when prompted, default is 'alpine')"
    scp -P 2222 resources/tools/$kloader tmp/pwnediBSS tmp/pwn.sh root@127.0.0.1:/
    [ $? == 1 ] && Error "Cannot connect to device via SSH. Please check your ~/.ssh/known_hosts file and try again" "You may also run: rm ~/.ssh/known_hosts"
    Log "Entering kDFU mode..."
    if [[ $VersionDetect == 1 ]]; then
        ssh -p 2222 root@127.0.0.1 "/pwn.sh; /$kloader /pwnediBSS" &
    else
        ssh -p 2222 root@127.0.0.1 "/$kloader /pwnediBSS" &
    fi
    echo
    echo "* Press POWER or HOME button when screen goes black on the device"
    
    Log "Finding device in DFU mode..."
    while [[ $DFUDevice != 1 ]]; do
        DFUDevice=$($lsusb | grep -ci '1227')
        sleep 2
    done
    Log "Found device in DFU mode."
    kill $iproxyPID
}

function Recovery {
    RecoveryDevice=$($lsusb | grep -ci '1281')
    if [[ $RecoveryDevice != 1 ]]; then
        Log "Entering recovery mode..."
        $ideviceenterrecovery $UniqueDeviceID >/dev/null
        while [[ $RecoveryDevice != 1 ]]; do
            RecoveryDevice=$($lsusb | grep -ci '1281')
            sleep 2
        done
    fi
    Log "A7 device in recovery mode detected. Get ready to enter DFU mode"
    read -p "[Input] Select Y to continue, N to exit recovery (Y/n) " RecoveryDFU
    if [[ $RecoveryDFU == n ]] || [[ $RecoveryDFU == N ]]; then
        Log "Exiting recovery mode."
        $irecovery -n
        exit
    fi
    echo "* Hold POWER and HOME button for 10 seconds."
    for i in {10..01}; do
        echo -n "$i "
        sleep 1
    done
    echo -e "\n* Release POWER and hold HOME button for 10 seconds."
    for i in {10..01}; do
        echo -n "$i "
        DFUDevice=$($lsusb | grep -ci '1227')
        [[ $DFUDevice == 1 ]] && CheckM8
        sleep 1
    done
    Error "Failed to detect device in DFU mode. Please run the script again"
}

function CheckM8 {
    DFUManual=1
    [[ $A7Device == 1 ]] && echo -e "\n[Log] Device in DFU mode detected."
    Log "Entering pwnDFU mode with ipwndfu..."
    cd resources/ipwndfu
    sudo $python ipwndfu -p
    pwnDFUDevice=$(sudo $lsusb -v -d 05ac:1227 2>/dev/null | grep -ci 'checkm8')
    if [ $pwnDFUDevice == 1 ]; then
        Log "Device in pwnDFU mode detected."
        if [[ $A7Device == 1 ]]; then
            Log "Running rmsigchks.py..."
            sudo $python rmsigchks.py
            cd ../..
        else
            kDFU iBSS
        fi
        Log "Downgrading device $ProductType in pwnDFU mode..."
        Mode='Downgrade'
        SelectVersion
    else
        Error "Failed to detect device in pwnDFU mode. Please run the script again" "./restore.sh Downgrade"
    fi    
}

function Downgrade {    
    if [[ $OSVer != 'Other' ]]; then
        [[ $ProductType == iPad4* ]] && IPSW="iPad_64bit"
        [[ $ProductType == iPhone6* ]] && IPSW="iPhone_64bit"
        [[ ! $IPSW ]] && IPSW="$ProductType" && SaveOTABlobs
        IPSW="${IPSW}_${OSVer}_${BuildVer}_Restore"
        IPSWCustom="${ProductType}_${OSVer}_${BuildVer}_Custom"
        if [ ! -e $IPSW.ipsw ]; then
            Log "iOS $OSVer IPSW cannot be found."
            echo "* If you already downloaded the IPSW, did you put it in the same directory as the script?"
            echo "* Do NOT rename the IPSW as the script will fail to detect it"
            Log "Downloading IPSW... (Press Ctrl+C to cancel)"
            curl -L $(cat $Firmware/$BuildVer/url) -o tmp/$IPSW.ipsw
            mv tmp/$IPSW.ipsw .
        fi
        if [ ! -e $IPSWCustom.ipsw ]; then
            Log "Verifying IPSW..."
            IPSWSHA1=$(cat $Firmware/$BuildVer/sha1sum)
            IPSWSHA1L=$(shasum $IPSW.ipsw | awk '{print $1}')
            [[ $IPSWSHA1L != $IPSWSHA1 ]] && Error "Verifying IPSW failed. Delete/replace the IPSW and run the script again"
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
    
    Log "Extracting IPSW..."
    unzip -q $IPSW.ipsw -d $IPSW/
    
    if [[ $A7Device == 1 ]]; then
        if [ ! -e $IPSWCustom.ipsw ]; then
            Log "Preparing custom IPSW..."
            cp $IPSW/Firmware/all_flash/$SEP .
            $bspatch $IPSW/Firmware/dfu/$iBSS.im4p $iBSS.im4p resources/patches/$iBSS.patch
            $bspatch $IPSW/Firmware/dfu/$iBEC.im4p $iBEC.im4p resources/patches/$iBEC.patch
            cp -f $iBSS.im4p $iBEC.im4p $IPSW/Firmware/dfu
            cd $IPSW
            zip ../$IPSWCustom.ipsw -rq0 *
            cd ..
            mv $IPSW $IPSWCustom
            IPSW=$IPSWCustom
        else
            cp $IPSW/Firmware/dfu/$iBSS.im4p .
            cp $IPSW/Firmware/dfu/$iBEC.im4p .
            cp $IPSW/Firmware/all_flash/$SEP .
        fi
        Log "Entering pwnREC mode..."
        $irecovery -f $iBSS.im4p
        $irecovery -f $iBEC.im4p
        sleep 5
        RecoveryDevice=$($lsusb | grep -ci '1281')
        if [[ $RecoveryDevice != 1 ]]; then
            echo "[Error] Failed to detect device in pwnREC mode."
            echo "* If you device has backlight turned on, you may try re-plugging in your device and attempt to continue"
            echo "* Press ENTER to continue (or press Ctrl+C to cancel)"
            read -s
            Log "Finding device in pwnREC mode..."
            while [[ $RecoveryDevice != 1 ]]; do
                RecoveryDevice=$($lsusb | grep -ci '1281')
                sleep 2
            done
        fi
        Log "Found device in pwnREC mode."
        SaveOTABlobs
    fi
    
    Log "Preparing for futurerestore... (Enter root password of your PC/Mac when prompted)"
    cd resources
    [[ $platform != win ]] && sudo bash -c "$python -m SimpleHTTPServer 80 &" || python3 -m http.server --bind 127.0.0.1 80 &
    cd ..
    
    if [ $Baseband == 0 ]; then
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
        elif [ ! -e saved/$ProductType/*.bbfw ]; then
            Log "Downloading baseband..."
            $partialzip $BasebandURL Firmware/$Baseband $Baseband 
            $partialzip $BasebandURL BuildManifest.plist BuildManifest.plist
            mkdir -p saved/$ProductType 2>/dev/null
            cp $Baseband BuildManifest.plist saved/$ProductType
        else
            cp saved/$ProductType/*.bbfw saved/$ProductType/BuildManifest.plist .
        fi
        BasebandSHA1L=$(shasum $Baseband | awk '{print $1}')
        Log "Proceeding to futurerestore..."
        if [ ! -e *.bbfw ] || [[ $BasebandSHA1L != $BasebandSHA1 ]]; then
            rm -f saved/$ProductType/*.bbfw saved/$ProductType/BuildManifest.plist
            echo "[Error] Downloading/verifying baseband failed."
            echo "* Your device is still in kDFU mode and you may run the script again"
            echo "* You can also continue and futurerestore can attempt to download the baseband again"
            echo "* Press ENTER to continue (or press Ctrl+C to cancel)"
            read -s
            if [[ $A7Device == 1 ]]; then
                $futurerestore2 -t $SHSH -s $SEP -m $BuildManifest --latest-baseband $IPSW.ipsw
            else
                $futurerestore1 -t $SHSH --latest-baseband --use-pwndfu $IPSW.ipsw
            fi
        elif [[ $A7Device == 1 ]]; then
            $futurerestore2 -t $SHSH -s $SEP -m $BuildManifest -b $Baseband -p $BuildManifest $IPSW.ipsw
        else
            $futurerestore1 -t $SHSH -b $Baseband -p BuildManifest.plist --use-pwndfu $IPSW.ipsw
        fi
    fi
        
    echo
    Log "futurerestore done!"    
    Log "Stopping local server... (Enter root password of your PC/Mac when prompted)"
    ps aux | awk '/python/ {print "sudo kill -9 "$2" 2>/dev/null"}' | bash
    Log "Downgrade script done!"
}

function InstallDependencies {
    echo "Install Dependencies"
    . /etc/os-release 2>/dev/null
    mkdir tmp 2>/dev/null
    cd tmp
    
    Log "Installing dependencies..."
    if [[ $ID == "arch" ]] || [[ $ID_LIKE == "arch" ]]; then
        # Arch Linux
        sudo pacman -Sy --noconfirm --needed bsdiff curl libcurl-compat libpng12 libimobiledevice libusbmuxd libzip openssh openssl-1.0 python2 unzip usbmuxd usbutils
        ln -sf /usr/lib/libcurl.so.3 ../resources/lib/libcurl.so.3
        ln -sf /usr/lib/libzip.so.5 ../resources/lib/libzip.so.4
        
    elif [[ $UBUNTU_CODENAME == "bionic" ]] || [[ $UBUNTU_CODENAME == "focal" ]]; then
        # Ubuntu Bionic and Focal
        sudo add-apt-repository universe
        sudo apt update
        sudo apt install -y autoconf automake binutils bsdiff build-essential checkinstall curl git libglib2.0-dev libimobiledevice-utils libplist3 libreadline-dev libtool-bin libusb-1.0-0-dev libusbmuxd-tools openssh-client usbmuxd usbutils
        SavePkg
        if [[ $UBUNTU_CODENAME == "bionic" ]]; then
            sudo apt install -y libzip4 python
            sudo dpkg -i libusbmuxd6.deb libpng12_bionic.deb libzip5.deb
            SaveFile https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/tools_linux_bionic.zip tools_linux_bionic.zip 685b422cae3ae3d15d6deda397d38ccc8fbcd5b2
            unzip tools_linux_bionic.zip -d ../resources/tools
        else
            sudo apt install -y libusbmuxd6 libzip5 python2
            sudo dpkg -i libssl1.0.0.deb libpng12.deb libzip4.deb
            ln -sf /usr/lib/x86_64-linux-gnu/libimobiledevice.so.6 ../resources/lib/libimobiledevice-1.0.so.6
            ln -sf /usr/lib/x86_64-linux-gnu/libplist.so.3 ../resources/lib/libplist-2.0.so.3
            ln -sf /usr/lib/x86_64-linux-gnu/libusbmuxd.so.6 ../resources/lib/libusbmuxd-2.0.so.6
        fi
        ar x libcurl3.deb data.tar.xz
        tar xf data.tar.xz
        cp usr/lib/x86_64-linux-gnu/libcurl.so.4.* ../resources/lib/libcurl.so.3
        
    elif [[ $ID == "fedora" ]]; then
        # Fedora 32
        sudo dnf install -y automake bsdiff git libimobiledevice-utils libpng12 libtool libusb-devel libusbmuxd-utils libzip make perl-Digest-SHA python2 readline-devel
        SavePkg
        rpm2cpio openssl-1.0.0.rpm | cpio -idmv
        cp usr/lib64/libcrypto.so.1.0.0 usr/lib64/libssl.so.1.0.0 ../resources/lib
        ln -sf /usr/lib64/libimobiledevice.so.6 ../resources/lib/libimobiledevice-1.0.so.6
        ln -sf /usr/lib64/libplist.so.3 ../resources/lib/libplist-2.0.so.3
        ln -sf /usr/lib64/libusbmuxd.so.6 ../resources/lib/libusbmuxd-2.0.so.6
        ln -sf /usr/lib64/libzip.so.5 ../resources/lib/libzip.so.4
        
    elif [[ $OSTYPE == "darwin"* ]]; then
        # macOS
        xcode-select --install
        SaveFile https://github.com/libimobiledevice-win32/imobiledevice-net/releases/download/v1.3.4/libimobiledevice.1.2.1-r1079-osx-x64.zip libimobiledevice.zip 2812e01fc7c09b5980b46b97236b2981dbec7307
        
    elif [[ $platform == "win" ]]; then
        # Windows MSYS2 MinGW64
        pacman -Sy --noconfirm --needed mingw-w64-x86_64-python openssh unzip
        SaveFile https://github.com/libimobiledevice-win32/imobiledevice-net/releases/download/v1.3.4/libimobiledevice.1.2.1-r1079-win-x64.zip libimobiledevice.zip 6d23f7d28e2212d9acc0723fe4f3fdec8e2ddeb8
        if [[ ! $(ls ../resources/tools/*win) ]]; then
            SaveFile https://github.com/LukeZGD/iOS-OTA-Downgrader/releases/download/tools/tools_win.zip tools_win.zip 92dd493c2128ad81255180b2536445dc1643ed55
            unzip tools_win.zip -d ../resources/tools
        fi
        ln -sf /mingw64/bin/libplist-2.0.dll /mingw64/bin/libplist.dll
        
    else
        Error "Distro not detected/supported by the install script." "See the repo README for supported OS versions/distros"
    fi
    
    if [[ $platform == linux ]]; then
        Compile libimobiledevice libirecovery
        ln -sf /usr/local/lib/libirecovery-1.0.so.3 ../resources/lib/libirecovery-1.0.so.3
    else
        rm -rf ../resources/libimobiledevice_$platform
        mkdir ../resources/libimobiledevice_$platform
        unzip libimobiledevice.zip -d ../resources/libimobiledevice_$platform
        chmod +x ../resources/libimobiledevice_$platform/*
    fi
    
    Log "Install script done! Please run the script again to proceed"
    exit
}

function Compile {
    git clone --depth 1 https://github.com/$1/$2.git
    cd $2
    ./autogen.sh
    sudo make install
    cd ..
    sudo rm -rf $2
}

function SaveExternal {
    ExternalURL="https://github.com/LukeZGD/$1.git"
    External=$1
    [[ $1 == "iOS-OTA-Downgrader-Keys" ]] && External="firmware"
    if [[ ! -d resources/$External ]] || [[ ! -d resources/$External/.git ]]; then
        Log "Downloading $External..."
        cd resources
        rm -rf $External
        git clone $ExternalURL $External
    else
        Log "Updating $External..."
        cd resources/$External
        git pull 2>/dev/null
        cd ..
    fi
    if [[ ! -e $External/README.md ]] || [[ ! -d $External/.git ]]; then
        Error "Downloading/updating $1 failed. Please run the script again"
    fi
    cd ..
}

function SaveFile {
    curl -L $1 -o $2
    if [[ $(shasum $2 | awk '{print $1}') != $3 ]]; then
        Error "Verifying failed. Please run the script again" "./restore.sh Install"
    fi
}

function SavePkg {
    if [[ ! -d ../saved/pkg ]]; then
        Log "Downloading packages..."
        SaveFile https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/depends_linux.zip depends_linux.zip c61825bdb41e34ee995ef183c7aca8183d76f8eb
        mkdir -p ../saved/pkg
        unzip depends_linux.zip -d ../saved/pkg
    fi
    cp ../saved/pkg/* .
}

function BasebandDetect {
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
    elif [ $ProductType == iPad4,1 ] || [ $ProductType == iPad4,2 ] || [ $ProductType == iPad4,3 ]; then
        iBSS="ipad4"
    elif [ $ProductType == iPad4,4 ] || [ $ProductType == iPad4,5 ]; then
        iBSS="ipad4b"
    else
        iBSS="$HWModel"
        iBSSBuildVer='12H321'
    fi
    iBEC="iBEC.$iBSS.RELEASE"
    iBSS="iBSS.$iBSS.RELEASE"
    SEP=sep-firmware.$HWModel.RELEASE.im4p
    
    if [[ $platform == win ]] && [[ $A7Device == 1 ]]; then
        Error "A7 devices are not supported on Windows." "Supports Linux and macOS only"
    fi
}

Main $1
