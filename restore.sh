#!/bin/bash
trap 'Clean; exit' INT TERM EXIT

function Clean {
    rm -rf iP*/ tmp/ $(ls *_${ProductType}_${OSVer}-*.shsh2 2>/dev/null) $(ls *_${ProductType}_${OSVer}-*.shsh 2>/dev/null) $(ls *.im4p 2>/dev/null) $(ls *.bbfw 2>/dev/null) BuildManifest.plist
}

function Error {
    echo "[Error] $1"
    [[ ! -z $2 ]] && echo "* $2"
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
    elif [[ $OSTYPE == "darwin"* ]]; then
        platform='macos'
    else
        Error "OSTYPE unknown/not supported." "Supports Linux and macOS only"
    fi
    cd resources/tools
    ln -sf futurerestore249_macos futurerestore152_macos
    cd ../..
    
    [[ ! $(ping -c1 google.com 2>/dev/null) ]] && Error "Please check your Internet connection before proceeding."
    [[ $(uname -m) != 'x86_64' ]] && Error "Only x86_64 distributions are supported. Use a 64-bit distro and try again"
    Clean
    mkdir tmp

    DFUDevice=$(lsusb | grep -c '1227')
    RecoveryDevice=$(lsusb | grep -c '1281')
    if [[ $1 == InstallDependencies ]] || [ ! $(which bspatch) ] || [ ! $(which ideviceinfo) ] ||
       [ ! $(which lsusb) ] || [ ! $(which ssh) ] || [ ! $(which python3) ]; then
        InstallDependencies
    elif [ $DFUDevice == 1 ] || [ $RecoveryDevice == 1 ]; then
        ProductType=$(sudo LD_LIBRARY_PATH=/usr/local/lib resources/tools/igetnonce_$platform)
        [ ! $ProductType ] && read -p "[Input] Enter ProductType (eg. iPad2,1): " ProductType
        UniqueChipID=$(sudo LD_LIBRARY_PATH=/usr/local/lib irecovery -q | grep 'ECID' | cut -c 7-)
        ProductVer='Unknown'
    else
        HWModel=$(ideviceinfo -s | grep 'HardwareModel' | cut -c 16- | tr '[:upper:]' '[:lower:]' | sed 's/.\{2\}$//')
        ProductType=$(ideviceinfo -s | grep 'ProductType' | cut -c 14-)
        [ ! $ProductType ] && ProductType=$(ideviceinfo | grep 'ProductType' | cut -c 14-)
        ProductVer=$(ideviceinfo -s | grep 'ProductVer' | cut -c 17-)
        VersionDetect=$(echo $ProductVer | cut -c 1)
        UniqueChipID=$(ideviceinfo -s | grep 'UniqueChipID' | cut -c 15-)
        UniqueDeviceID=$(ideviceinfo -s | grep 'UniqueDeviceID' | cut -c 17-)
    fi
    [ ! $ProductType ] && ProductType='NA'
    BasebandDetect
    
    chmod +x resources/tools/*
    SaveExternal firmware
    SaveExternal ipwndfu
    
    if [ $DFUDevice == 1 ]; then
        Log "Device in DFU mode detected."
        if [[ $A7Device != 1 ]]; then
            read -p "[Input] Is this a 32-bit device in kDFU mode? (y/N) " DFUManual
            if [[ $DFUManual == y ]] || [[ $DFUManual == Y ]]; then
                Log "Downgrading device $ProductType in kDFU mode..."
                Mode='Downgrade'
                SelectVersion
            else
                Error "Please put the device in normal mode (and jailbroken for 32-bit) before proceeding." "Recovery or DFU mode is also applicable for A7 devices"
            fi
        fi
    elif [ $RecoveryDevice == 1 ] && [[ $A7Device != 1 ]]; then
        Error "Non-A7 device detected in recovery mode. Please put the device in normal mode and jailbroken before proceeding"
    fi
    
    echo "* HardwareModel: ${HWModel}ap"
    echo "* ProductType: $ProductType"
    echo "* ProductVersion: $ProductVer"
    echo "* UniqueChipID (ECID): $UniqueChipID"
    echo
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
                "(Re-)Install Dependencies" ) InstallDependencies; exit;;
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
    fi
    Selection=("iOS 8.4.1")
    if [ $ProductType == iPad2,1 ] || [ $ProductType == iPad2,2 ] ||
       [ $ProductType == iPad2,3 ] || [ $ProductType == iPhone4,1 ]; then
        Selection+=("iOS 6.1.3")
    fi
    [[ $Mode == 'Downgrade' ]] && Selection+=("Other")
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
        read -p "[Input] Path to IPSW (drag IPSW to terminal window): " IPSW
        IPSW="$(basename $IPSW .ipsw)"
        read -p "[Input] Path to SHSH (drag SHSH to terminal window): " SHSH
    elif [[ $A7Device == 1 ]] && [[ $pwnDFUDevice != 1 ]]; then
        if [[ $DFUDevice == 1 ]]; then
            CheckM8
        else
            Recovery
        fi
    fi
    
    if [ $ProductType == iPod5,1 ]; then
        iBSS="iBSS.${HWModel}ap.RELEASE"
        iBSSBuildVer='10B329'
    elif [ $ProductType == iPad3,1 ]; then
        iBSS="iBSS.${HWModel}ap.RELEASE"
        iBSSBuildVer='11D257'
    elif [ $ProductType == iPhone6,1 ] || [ $ProductType == iPhone6,2 ]; then
        iBSS="iBSS.iphone6.RELEASE"
        iBEC="iBEC.iphone6.RELEASE"
    elif [ $ProductType == iPad4,1 ] || [ $ProductType == iPad4,2 ] || [ $ProductType == iPad4,3 ]; then
        iBSS="iBSS.ipad4.RELEASE"
        iBEC="iBEC.ipad4.RELEASE"
    elif [ $ProductType == iPad4,4 ] || [ $ProductType == iPad4,5 ]; then
        iBSS="iBSS.ipad4b.RELEASE"
        iBEC="iBEC.ipad4b.RELEASE"
    else
        iBSS="iBSS.$HWModel.RELEASE"
        iBSSBuildVer='12H321'
    fi
    IV=$(cat $Firmware/$iBSSBuildVer/iv 2>/dev/null)
    Key=$(cat $Firmware/$iBSSBuildVer/key 2>/dev/null)
    
    if [[ $Mode == 'Downgrade' ]]; then
        Downgrade
    elif [[ $Mode == 'SaveOTABlobs' ]]; then
        SaveOTABlobs
    elif [[ $Mode == 'kDFU' ]]; then
        kDFU
    fi
    exit
}

function SaveOTABlobs {
    Log "Saving $OSVer blobs with tsschecker..."
    BuildManifest="resources/manifests/BuildManifest_${ProductType}_${OSVer}.plist"
    if [ $A7Device == 1 ]; then
        APNonce=$(sudo LD_LIBRARY_PATH=/usr/local/lib irecovery -q | grep 'NONC' | cut -c 7-)
        echo "* APNonce: $APNonce"
        env LD_LIBRARY_PATH=/usr/local/lib resources/tools/tsschecker_$platform -d $ProductType -B ${HWModel}ap -i $OSVer -e $UniqueChipID -m $BuildManifest --apnonce $APNonce -o -s
    else
        env LD_LIBRARY_PATH=/usr/local/lib resources/tools/tsschecker_$platform -d $ProductType -i $OSVer -e $UniqueChipID -m $BuildManifest -o -s
        SHSH=$(ls *_${ProductType}_${OSVer}-*.shsh2)
    fi
    [ ! $SHSH ] && SHSH=$(ls *_${ProductType}_${HWModel}ap_${OSVer}-*.shsh)
    [ ! $SHSH ] && Error "Saving $OSVer blobs failed. Please run the script again" "It is also possible that $OSVer for $ProductType is no longer signed"
    mkdir -p saved/shsh 2>/dev/null
    cp "$SHSH" saved/shsh
    Log "Successfully saved $OSVer blobs."
}

function kDFU {
    if [ ! -e saved/$ProductType/$iBSS.dfu ]; then
        Log "Downloading iBSS..."
        resources/tools/pzb_$platform -g Firmware/dfu/${iBSS}.dfu -o $iBSS.dfu $(cat $Firmware/$iBSSBuildVer/url)
        mkdir -p saved/$ProductType 2>/dev/null
        mv $iBSS.dfu saved/$ProductType
    fi
    Log "Decrypting iBSS..."
    Log "IV = $IV"
    Log "Key = $Key"
    resources/tools/xpwntool_$platform saved/$ProductType/$iBSS.dfu tmp/iBSS.dec -k $Key -iv $IV
    Log "Patching iBSS..."
    bspatch tmp/iBSS.dec tmp/pwnediBSS resources/patches/$iBSS.patch
    
    # Regular kloader only works on iOS 6 to 9, so other versions are provided for iOS 5 and 10
    if [[ $VersionDetect == 1 ]]; then
        kloader='kloader_hgsp'
    elif [[ $VersionDetect == 5 ]]; then
        kloader='kloader5'
    else
        kloader='kloader'
    fi

    if [[ $VersionDetect == 1 ]]; then
        # ifuse+MTerminal is used instead of SSH for devices on iOS 10
        [ ! $(which ifuse) ] && Error "One of the dependencies (ifuse) cannot be found. Please re-install dependencies and try again" "For macOS systems, install osxfuse and ifuse with brew"
        WifiAddr=$(ideviceinfo -s | grep 'WiFiAddress' | cut -c 14-)
        WifiAddrDecr=$(echo $(printf "%x\n" $(expr $(printf "%d\n" 0x$(echo "${WifiAddr}" | tr -d ':')) - 1)) | sed 's/\(..\)/\1:/g;s/:$//')
        echo '#!/bin/bash' > tmp/pwn.sh
        echo "nvram wifiaddr=$WifiAddrDecr
        chmod 755 kloader_hgsp
        ./kloader_hgsp pwnediBSS" >> tmp/pwn.sh
        Log "Mounting device with ifuse..."
        mkdir mount
        ifuse mount
        Log "Copying stuff to device..."
        cp "tmp/pwn.sh" "resources/tools/$kloader" "tmp/pwnediBSS" "mount/"
        Log "Unmounting device... (Enter root password of your PC/Mac when prompted)"
        sudo umount mount
        echo
        echo "* Open MTerminal and run these commands:"
        echo
        echo '$ su'
        echo "(Enter root password of your iOS device, default is 'alpine')"
        echo "# cd Media"
        echo "# chmod +x pwn.sh"
        echo "# ./pwn.sh"
    else
        # SSH kloader and pwnediBSS
        echo "* Make sure SSH is installed and working on the device!"
        echo "* Please enter Wi-Fi IP address of device for SSH connection"
        read -p "[Input] IP Address: " IPAddress
        Log "Connecting to device via SSH... (Enter root password of your iOS device, default is 'alpine')"
        Log "Copying stuff to device..."
        scp resources/tools/$kloader tmp/pwnediBSS root@$IPAddress:/
        [ $? == 1 ] && Error "Cannot connect to device via SSH." "Please check your ~/.ssh/known_hosts file and try again"
        Log "Entering kDFU mode..."
        ssh root@$IPAddress "chmod 755 /$kloader && /$kloader /pwnediBSS" &
    fi
    echo
    echo "* Press home/power button once when screen goes black on the device"
    
    Log "Finding device in DFU mode..."
    while [[ $DFUDevice != 1 ]]; do
        DFUDevice=$(lsusb | grep -c '1227')
        sleep 2
    done
    Log "Found device in DFU mode."
}

function Recovery {
    RecoveryDevice=$(lsusb | grep -c '1281')
    if [[ $RecoveryDevice != 1 ]]; then
        Log "Entering recovery mode..."
        ideviceenterrecovery $UniqueDeviceID >/dev/null
        while [[ $RecoveryDevice != 1 ]]; do
            RecoveryDevice=$(lsusb | grep -c '1281')
            sleep 2
        done
    fi
    Log "A7 device in recovery mode detected. Get ready to enter DFU mode"
    read -p "[Input] Select Y to continue, N to exit recovery (Y/n) " RecoveryDFU
    if [[ $RecoveryDFU == n ]] || [[ $RecoveryDFU == N ]]; then
        Log "Exiting recovery mode."
        sudo LD_LIBRARY_PATH=/usr/local/lib irecovery -n
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
        DFUDevice=$(lsusb | grep -c '1227')
        sleep 1
        if [[ $DFUDevice == 1 ]]; then
            echo -e "\n[Log] Device in DFU mode detected."
            CheckM8
        fi
    done
    echo -e "\n[Error] Failed to detect device in DFU mode. Please run the script again"
    exit
}

function CheckM8 {
    DFUManual=0
    Log "Entering pwnDFU mode with ipwndfu..."
    cd resources/ipwndfu
    sudo python2 ipwndfu -p
    pwnDFUDevice=$(sudo lsusb -v -d 05ac:1227 2>/dev/null | grep -c 'checkm8')
    if [ $pwnDFUDevice == 1 ]; then
        Log "Detected device in pwnDFU mode. Running rmsigchks.py..."
        sudo python2 rmsigchks.py
        cd ../..
        Log "Downgrading device $ProductType in pwnDFU mode..."
        Mode='Downgrade'
        SelectVersion
    else
        Error "Entering pwnDFU failed. Please run the script again" '$ ./restore.sh Downgrade'
    fi    
}

function Downgrade {    
    if [[ $OSVer != 'Other' ]]; then
        if [[ $ProductType == iPad4* ]]; then
            IPSW="iPad_64bit"
        elif [[ $ProductType == iPhone6* ]]; then
            IPSW="iPhone_64bit"
        else
            IPSW="${ProductType}"
            SaveOTABlobs
        fi
        IPSW="${IPSW}_${OSVer}_${BuildVer}_Restore"
        IPSWCustom="${ProductType}_${OSVer}_${BuildVer}_Custom"
        if [ ! -e $IPSW.ipsw ]; then
            Log "iOS $OSVer IPSW cannot be found. Downloading IPSW..."
            curl -L $(cat $Firmware/$BuildVer/url) -o tmp/$IPSW.ipsw
            mv tmp/$IPSW.ipsw .
        fi
        if [ ! -e $IPSWCustom.ipsw ]; then
            Log "Verifying IPSW..."
            IPSWSHA1=$(cat $Firmware/$BuildVer/sha1sum)
            IPSWSHA1L=$(sha1sum $IPSW.ipsw | awk '{print $1}')
            [[ $IPSWSHA1L != $IPSWSHA1 ]] && Error "Verifying IPSW failed. Delete/replace the IPSW and run the script again"
        else
            IPSW=$IPSWCustom
        fi
        if [ ! $DFUManual ]; then
            Log "Extracting iBSS from IPSW..."
            mkdir -p saved/$ProductType 2>/dev/null
            unzip -o -j $IPSW.ipsw Firmware/dfu/$iBSS.dfu -d saved/$ProductType
        fi
    fi
    
    [ ! $DFUManual ] && kDFU
    
    Log "Extracting IPSW..."
    unzip -q $IPSW.ipsw -d $IPSW/
    
    if [ $A7Device == 1 ]; then
        if [ ! -e $IPSWCustom.ipsw ]; then
            Log "Preparing custom IPSW..."
            cp $IPSW/Firmware/all_flash/$SEP .
            bspatch $IPSW/Firmware/dfu/$iBSS.im4p $iBSS.im4p resources/patches/$iBSS.patch
            bspatch $IPSW/Firmware/dfu/$iBEC.im4p $iBEC.im4p resources/patches/$iBEC.patch
            cp -f $iBSS.im4p $iBEC.im4p $IPSW/Firmware/dfu
            cd $IPSW
            zip ../$IPSWCustom.ipsw -r0 *
            cd ..
            mv $IPSW $IPSWCustom
            IPSW=$IPSWCustom
        else
            cp $IPSW/Firmware/dfu/$iBSS.im4p .
            cp $IPSW/Firmware/dfu/$iBEC.im4p .
            cp $IPSW/Firmware/all_flash/$SEP .
        fi
        Log "Entering PWNREC mode..."
        sudo LD_LIBRARY_PATH=/usr/local/lib irecovery -f $iBSS.im4p
        sudo LD_LIBRARY_PATH=/usr/local/lib irecovery -f $iBEC.im4p
        sleep 5
        RecoveryDevice=$(lsusb | grep -c '1281')
        if [[ $RecoveryDevice != 1 ]]; then
            echo -e "\n[Error] Failed to send iBSS/iBEC. Please try again"
            exit
        fi
        SaveOTABlobs
    fi
    
    Log "Preparing for futurerestore... (Enter root password of your PC/Mac when prompted)"
    cd resources
    sudo bash -c "python3 -m http.server 80 &"
    cd ..
    
    if [ $Baseband == 0 ]; then
        Log "Device $ProductType has no baseband"
        Log "Proceeding to futurerestore..."
        if [ $A7Device == 1 ]; then
            sudo LD_LIBRARY_PATH=/usr/local/lib resources/tools/futurerestore249_$platform -t $SHSH -s $SEP -m $BuildManifest --no-baseband $IPSW.ipsw
        else
            sudo LD_PRELOAD=libcurl.so.3 resources/tools/futurerestore152_$platform -t $SHSH --no-baseband --use-pwndfu $IPSW.ipsw
        fi
    else
        if [ $A7Device == 1 ]; then
            cp $IPSW/Firmware/$Baseband .
        elif [ ! saved/$ProductType/*.bbfw ]; then
            Log "Downloading baseband..."
            resources/tools/pzb_$platform -g Firmware/$Baseband -o $Baseband $BasebandURL
            resources/tools/pzb_$platform -g BuildManifest.plist -o BuildManifest.plist $BasebandURL
            mkdir -p saved/$ProductType 2>/dev/null
            cp $Baseband BuildManifest.plist saved/$ProductType
        else
            cp saved/$ProductType/*.bbfw saved/$ProductType/BuildManifest.plist .
        fi
        BasebandSHA1L=$(sha1sum $Baseband | awk '{print $1}')
        if [ ! *.bbfw ] || [[ $BasebandSHA1L != $BasebandSHA1 ]]; then
            rm -f saved/$ProductType/*.bbfw saved/$ProductType/BuildManifest.plist
            echo "[Error] Downloading/verifying baseband failed."
            echo "* Your device is still in kDFU mode and you may run the script again"
            echo "* You can also continue and futurerestore can attempt to download the baseband again"
            echo "* Proceeding to futurerestore in 10 seconds (Press Ctrl+C to cancel)"
            sleep 10
            Log "Proceeding to futurerestore..."
            if [ $A7Device == 1 ]; then
                sudo LD_LIBRARY_PATH=/usr/local/lib resources/tools/futurerestore249_$platform -t $SHSH -s $SEP -m $BuildManifest --latest-baseband $IPSW.ipsw
            else
                sudo LD_PRELOAD=libcurl.so.3 resources/tools/futurerestore152_$platform -t $SHSH --latest-baseband --use-pwndfu $IPSW.ipsw
            fi
        elif [ $A7Device == 1 ]; then
            Log "Proceeding to futurerestore..."
            sudo LD_LIBRARY_PATH=/usr/local/lib resources/tools/futurerestore249_$platform -t $SHSH -s $SEP -m $BuildManifest -b $Baseband -p $BuildManifest $IPSW.ipsw
        else
            Log "Proceeding to futurerestore..."
            sudo LD_PRELOAD=libcurl.so.3 resources/tools/futurerestore152_$platform -t $SHSH -b $Baseband -p BuildManifest.plist --use-pwndfu $IPSW.ipsw
        fi
    fi
        
    echo
    Log "futurerestore done!"    
    Log "Stopping local server... (Enter root password of your PC/Mac when prompted)"
    ps aux | awk '/python3/ {print "sudo kill -9 "$2" 2>/dev/null"}' | bash
    Log "Downgrade script done!"
}

function InstallDependencies {
    echo "Install Dependencies"
    . /etc/os-release 2>/dev/null
    cd tmp
    
    Log "Installing dependencies..."
    if [[ $ID == "arch" ]] || [[ $ID_LIKE == "arch" ]]; then
        # Arch Linux
        sudo pacman -Sy --noconfirm --needed bsdiff curl libcurl-compat libpng12 libimobiledevice libzip openssh openssl-1.0 python2 python unzip usbmuxd usbutils
        Compile libimobiledevice ifuse
        sudo ln -sf /usr/lib/libzip.so.5 /usr/lib/libzip.so.4
        
    elif [[ $VERSION_ID == "20.04" ]]; then
        # Ubuntu Focal
        sudo add-apt-repository universe
        sudo apt update
        sudo apt -y install autoconf automake binutils bsdiff build-essential checkinstall curl git ifuse libimobiledevice-utils libplist3 libreadline-dev libtool-bin libusb-1.0-0-dev libusbmuxd6 libzip5 openssh-client python2 python3 usbmuxd usbutils
        SavePkg http://archive.ubuntu.com/ubuntu/pool/universe/c/curl3/libcurl3_7.58.0-2ubuntu2_amd64.deb libcurl3.deb
        VerifyPkg libcurl3.deb f6ab4c77f7c4680e72f9dd754f706409c8598a9f
        ar x libcurl3.deb data.tar.xz
        tar xf data.tar.xz
        sudo cp usr/lib/x86_64-linux-gnu/libcurl.so.4.* /usr/lib/libcurl.so.3
        SavePkg http://ppa.launchpad.net/linuxuprising/libpng12/ubuntu/pool/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1.1+1~ppa0~focal_amd64.deb libpng12.deb
        VerifyPkg libpng12.deb 4ceaaa02d2af09d0cdf1074372ed5df10b90b088
        SavePkg http://archive.ubuntu.com/ubuntu/pool/main/o/openssl1.0/libssl1.0.0_1.0.2n-1ubuntu5.3_amd64.deb libssl1.0.0.deb
        VerifyPkg libssl1.0.0.deb 573f3b5744c4121431179abee144543fc662e8b1
        SavePkg http://archive.ubuntu.com/ubuntu/pool/universe/libz/libzip/libzip4_1.1.2-1.1_amd64.deb libzip4.deb
        VerifyPkg libzip4.deb 449ce0b3de6772f6fab0ec680fde641fb3428a28
        sudo dpkg -i libpng12.deb libssl1.0.0.deb libzip4.deb
        sudo ln -sf /usr/lib/x86_64-linux-gnu/libimobiledevice.so.6 /usr/local/lib/libimobiledevice-1.0.so.6
        sudo ln -sf /usr/lib/x86_64-linux-gnu/libplist.so.3 /usr/local/lib/libplist-2.0.so.3
        sudo ln -sf /usr/lib/x86_64-linux-gnu/libusbmuxd.so.6 /usr/local/lib/libusbmuxd-2.0.so.6
        
    elif [[ $ID == "fedora" ]]; then
        sudo dnf install -y automake bsdiff git ifuse libimobiledevice-utils libpng12 libtool libusb-devel libzip make python2 readline-devel
        SavePkg http://ftp.pbone.net/mirror/ftp.scientificlinux.org/linux/scientific/6.1/x86_64/os/Packages/openssl-1.0.0-10.el6.x86_64.rpm openssl-1.0.0.rpm
        VerifyPkg openssl-1.0.0.rpm 10e7e37c0eac8e7ea8c0657596549d7fe9dac454
        rpm2cpio openssl-1.0.0.rpm | cpio -idmv
        sudo cp usr/lib64/libcrypto.so.1.0.0 usr/lib64/libssl.so.1.0.0 /usr/lib64
        sudo ln -sf /usr/lib64/libimobiledevice.so.6 /usr/local/lib/libimobiledevice-1.0.so.6
        sudo ln -sf /usr/lib64/libplist.so.3 /usr/local/lib/libplist-2.0.so.3
        sudo ln -sf /usr/lib64/libusbmuxd.so.6 /usr/local/lib/libusbmuxd-2.0.so.6
        sudo ln -sf /usr/lib64/libzip.so.5 /usr/lib64/libzip.so.4
        
    elif [[ $OSTYPE == "darwin"* ]]; then
        # macOS
        if [[ ! $(which brew) ]]; then
            Log "Homebrew is not detected/installed, installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
        fi
        brew uninstall --ignore-dependencies usbmuxd
        brew uninstall --ignore-dependencies libimobiledevice
        brew install --HEAD usbmuxd
        brew install --HEAD libimobiledevice
        brew install libzip lsusb md5sha1sum python3
        brew install make automake autoconf libtool pkg-config gcc
        brew cask install osxfuse
        brew install ifuse
        
    else
        Error "Distro not detected/supported by the install script." "See the repo README for OS versions/distros tested on"
    fi
    
    Compile libimobiledevice libirecovery
    [[ $platform == linux ]] && sudo cp ../resources/lib/* /usr/local/lib
    
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
    if [[ ! $(ls resources/$1 2>/dev/null) ]]; then
        if [[ $1 == 'ipwndfu' ]]; then
            ExternalURL="https://github.com/LukeZGD/ipwndfu/archive/master.zip"
            ExternalFile="ipwndfu-master"
        else
            ExternalURL="https://github.com/LukeZGD/iOS-OTA-Downgrader/archive/$1.zip"
            ExternalFile="iOS-OTA-Downgrader-$1"
        fi
        Log "Downloading $1..."
        curl -Ls $ExternalURL -o tmp/$ExternalFile.zip
        unzip -q tmp/$ExternalFile.zip -d tmp
        mkdir resources/$1
        mv tmp/$ExternalFile/* resources/$1
    fi
}

function SavePkg {
    if [[ ! -e ../saved/pkg/$2 ]]; then
        mkdir -p ../saved/pkg 2>/dev/null
        Log "Downloading $1..."
        curl -L $1 -o $2
        cp $2 ../saved/pkg
    else
        cp ../saved/pkg/$2 .
    fi
}

function VerifyPkg {
    Log "Verifying $1..."
    if [[ $(sha1sum $1 | awk '{print $1}') != $2 ]]; then
        rm -f ../saved/pkg/$1
        Error "Verifying $1 failed. Please run the script again" '$ ./restore.sh InstallDependencies'
    fi
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
    elif [ $ProductType == 'NA' ]; then
        Error "Please put the device in normal mode (and jailbroken for 32-bit) before proceeding." "Recovery or DFU mode is also applicable for A7 devices"
    elif [ $ProductType != iPad2,1 ] && [ $ProductType != iPad2,4 ] && [ $ProductType != iPad2,5 ] &&
         [ $ProductType != iPad3,1 ] && [ $ProductType != iPad3,4 ] && [ $ProductType != iPod5,1 ]; then
        Error "Your device $ProductType is not supported."
    fi
    [ $ProductType == iPhone6,1 ] && HWModel=n51
    [ $ProductType == iPhone6,2 ] && HWModel=n53
    [ $ProductType == iPad4,1 ] && HWModel=j71
    [ $ProductType == iPad4,2 ] && HWModel=j72
    [ $ProductType == iPad4,3 ] && HWModel=j73
    [ $ProductType == iPad4,4 ] && HWModel=j85
    [ $ProductType == iPad4,5 ] && HWModel=j86
    SEP=sep-firmware.$HWModel.RELEASE.im4p
}

Main $1
