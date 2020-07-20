#!/bin/bash
trap 'Clean; exit' INT TERM EXIT

function Clean {
    rm -rf iP*/ tmp/ $(ls *_${ProductType}_${OSVer}-*.shsh2 2>/dev/null) $(ls *.im4p 2>/dev/null) $(ls *.bbfw 2>/dev/null) BuildManifest.plist
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
    [[ ! $(ping -c1 google.com 2>/dev/null) ]] && Error "Please check your Internet connection before proceeding."
    [[ $(uname -m) != 'x86_64' ]] && Error "Only x86_64 distributions are supported. Use a 64-bit distro and try again"
    Clean
    mkdir tmp

    DFUDevice=$(lsusb | grep -c '1227')
    RecoveryDevice=$(lsusb | grep -c '1281')
    if [ $DFUDevice == 1 ] || [ $RecoveryDevice == 1 ]; then
        UniqueChipID=$(sudo LD_LIBRARY_PATH=/usr/local/lib irecovery -q | grep 'ECID' | cut -c 9-)
    else
        HWModel=$(ideviceinfo -s | grep 'HardwareModel' | cut -c 16- | tr '[:upper:]' '[:lower:]' | sed 's/.\{2\}$//')
        ProductType=$(ideviceinfo -s | grep 'ProductType' | cut -c 14-)
        [ ! $ProductType ] && ProductType=$(ideviceinfo | grep 'ProductType' | cut -c 14-)
        # ProductType=iPhone5,2; HWModel=n42 # Test mode
        ProductVer=$(ideviceinfo -s | grep 'ProductVer' | cut -c 17-)
        VersionDetect=$(echo $ProductVer | cut -c 1)
        UniqueChipID=$(ideviceinfo -s | grep 'UniqueChipID' | cut -c 15-)
        UniqueDeviceID=$(ideviceinfo -s | grep 'UniqueDeviceID' | cut -c 17-)
        rm -f resources/ProductType
    fi
    
    if [ ! $(which bspatch) ] || [ ! $(which ideviceinfo) ] || [ ! $(which lsusb) ] || [ ! $(which ssh) ] || [ ! $(which python3) ]; then
        InstallDependencies
    else
        chmod +x resources/tools/*
        SaveExternal firmware
        SaveExternal ipwndfu
        MainMenu
    fi
}

function MainMenu {    
    if [ $DFUDevice == 1 ]; then
        Log "Device in DFU mode detected."
        GetProductType
        BasebandDetect
        if [ $A7Device == 1 ]; then
            CheckM8
        fi
        read -p "[Input] Is this a 32-bit device in kDFU mode? (y/N) " DFUManual
        if [[ $DFUManual == y ]] || [[ $DFUManual == Y ]]; then
            Log "Downgrading device $ProductType in kDFU mode..."
            Mode='Downgrade'
            SelectVersion
        else
            Error "Please put the device in normal mode (and jailbroken, 32-bit only) before proceeding." "Recovery or DFU mode is also applicable for A7 devices"
        fi
    elif [ $RecoveryDevice == 1 ]; then
        if [ $A7Device == 1 ]; then
            GetProductType
            BasebandDetect
            Recovery
        else
            Error "Non-A7 device detected in recovery mode. Please put the device in normal mode and jailbroken before proceeding" 
        fi
    elif [ ! $ProductType ]; then
        Error "Please put the device in normal mode (and jailbroken, 32-bit only) before proceeding." "Recovery and DFU modes are also applicable for A7 devices"
    fi
    BasebandDetect
    
    echo "Main Menu"
    echo
    echo "HardwareModel: ${HWModel}ap"
    echo "ProductType: $ProductType"
    echo "ProductVersion: $ProductVer"
    echo "UniqueChipID (ECID): $UniqueChipID"
    echo
    echo "[Input] Select an option:"
    select opt in "Downgrade device" "Save OTA blobs" "(Re-)Install Dependencies" "(Any other key to exit)"; do
        case $opt in
            "Downgrade device" ) Mode='Downgrade'; break;;
            "Save OTA blobs" ) Mode='SaveOTABlobs'; break;;
            "(Re-)Install Dependencies" ) InstallDependencies; exit;;
            * ) exit;;
        esac
    done
    SelectVersion
}

function SelectVersion {
    if [[ $ProductType == iPad4* ]] || [[ $ProductType == iPhone6* ]]; then
        OSVer='10.3.3'
        BuildVer='14G60'
        Action
    fi
    Selection=("iOS 8.4.1")
    if [[ $Mode == 'kDFU' ]]; then
        Action
    elif [ $ProductType == iPad2,1 ] || [ $ProductType == iPad2,2 ] ||
         [ $ProductType == iPad2,3 ] || [ $ProductType == iPhone4,1 ]; then
        Selection+=("iOS 6.1.3")
    fi
    [[ $Mode == 'Downgrade' ]] && Selection+=("Other")
    Selection+=("Back")
    echo "[Input] Select iOS version:"
    select opt in "${Selection[@]}"; do
        case $opt in
            "iOS 8.4.1" ) OSVer='8.4.1'; BuildVer='12H321'; break;;
            "iOS 6.1.3" ) OSVer='6.1.3'; BuildVer='10B329'; break;;
            "Other" ) OSVer='Other'; break;;
            "Back" ) MainMenu; break;;
            *) exit;;
        esac
    done
    Action
}

function Action {    
    Log "Option: $Mode"
    if [[ $OSVer == 'Other' ]]; then
        echo "Move/copy the IPSW and SHSH to the directory where the script is located"
        read -p "[Input] Path to IPSW (drag IPSW to terminal window): " IPSW
        IPSW="$(basename $IPSW .ipsw)"
        read -p "[Input] Path to SHSH (drag SHSH to terminal window): " SHSH
    elif [ $A7Device == 1 ] && [ $pwnDFUDevice != 1 ] && [[ $Mode == 'Downgrade' ]]; then
        Recovery
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
    elif [ $ProductType == iPad4,4 ] || [ $ProductType == iPad4,5 ] || [ $ProductType == iPad4,6 ]; then
        iBSS="iBSS.ipad4b.RELEASE"
        iBEC="iBEC.ipad4b.RELEASE"
    else
        iBSS="iBSS.$HWModel.RELEASE"
        iBSSBuildVer='12H321'
    fi
    IV=$(cat $Firmware/$iBSSBuildVer/iv)
    Key=$(cat $Firmware/$iBSSBuildVer/key)
    
    if [[ $Mode == 'Downgrade' ]]; then
        Downgrade
    elif [[ $Mode == 'SaveOTABlobs' ]]; then
        SaveOTABlobs
    fi
    exit
}

function SaveOTABlobs {
    Log "Saving $OSVer blobs with tsschecker..."
    BuildManifest="resources/manifests/BuildManifest_${ProductType}_${OSVer}.plist"
    if [ $A7Device == 1 ]; then
        APNonce=$(sudo LD_LIBRARY_PATH=/usr/local/lib irecovery -q | grep 'NONC' | cut -c 9-)
        Log "APNonce: $APNonce"
    fi
    if [ $ProductType == iPad4,3 ]; then
        resources/tools/tsschecker_$platform -d iPad4,3 --boardconfig j73AP -i $OSVer -o -s $UniqueChipID -m $BuildManifest --apnonce $APNonce
    elif [ $A7Device == 1 ]; then
        resources/tools/tsschecker_$platform -d $ProductType -i $OSVer -o -s $UniqueChipID -m $BuildManifest --apnonce $APNonce
    else
        resources/tools/tsschecker_$platform -d $ProductType -i $OSVer -o -s $UniqueChipID -m $BuildManifest
    fi
    SHSH=$(ls *_${ProductType}_${OSVer}-*.shsh2)
    [ ! "$SHSH" ] && Error "Saving $OSVer blobs failed. Please run the script again" "It is also possible that $OSVer for $ProductType is no longer signed"
    mkdir -p saved/shsh 2>/dev/null
    cp "$SHSH" saved/shsh
    Log "Successfully saved $OSVer blobs."
}

function kDFU {
    if [ ! saved/$ProductType/$iBSS.dfu ]; then
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
        Log "Open MTerminal and run these commands:"
        echo
        echo '$ su'
        echo "(Enter root password of your iOS device, default is 'alpine')"
        echo "# cd Media"
        echo "# chmod +x pwn.sh"
        echo "# ./pwn.sh"
    else
        # SSH kloader and pwnediBSS
        echo "Make sure SSH is installed and working on the device!"
        echo "Please enter Wi-Fi IP address of device for SSH connection"
        read -p "[Input] IP Address: " IPAddress
        Log "Connecting to device via SSH... (Enter root password of your iOS device, default is 'alpine')"
        Log "Copying stuff to device..."
        scp resources/tools/$kloader tmp/pwnediBSS root@$IPAddress:/
        [ $? == 1 ] && Error "Cannot connect to device via SSH." "Please check your ~/.ssh/known_hosts file and try again"
        Log "Entering kDFU mode..."
        ssh root@$IPAddress "chmod 755 /$kloader && /$kloader /pwnediBSS" &
    fi
    echo
    echo "Press home/power button once when screen goes black on the device"
    
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
        ideviceenterrecovery $UniqueDeviceID 2>/dev/null
        while [[ $RecoveryDevice != 1 ]]; do
            RecoveryDevice=$(lsusb | grep -c '1281')
            sleep 2
        done
    fi
    Log "A7 device in recovery mode detected. Get ready to enter DFU mode"
    read -p "[Input] Select Y to continue, N to exit recovery (y/N) " RecoveryDFU
    if [[ $RecoveryDFU == y ]] || [[ $RecoveryDFU == y ]]; then
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
        echo -e "\n[Error] Entering DFU mode failed. Please run the script again"
        exit
    else
        Log "Exiting recovery mode."
        sudo LD_LIBRARY_PATH=/usr/local/lib irecovery -n
        exit
    fi
}

function CheckM8 {
    DFUManual=0
    pwnDFUDevice=$(sudo lsusb -v -d 05ac:1227 | grep -c 'checkm8')
    Log "Entering pwnDFU mode with ipwndfu..."
    cd resources/ipwndfu
    sudo python2 ipwndfu -p
    pwnDFUDevice=$(sudo lsusb -v -d 05ac:1227 | grep -c 'checkm8')
    if [ $pwnDFUDevice == 1 ]; then
        Log "Detected device in pwnDFU mode. Running rmsigchks.py..."
        sudo python2 rmsigchks.py
        cd ../..
        Log "Downgrading device $ProductType in kDFU mode..."
        Mode='Downgrade'
        SelectVersion
    else
        echo $ProductType > resources/ProductType
        Error "Entering pwnDFU failed. Please run the script again"
    fi    
}

function Downgrade {    
    if [ $OSVer != 'Other' ]; then
        [ $A7Device != 1 ] && SaveOTABlobs
        IPSW="${ProductType}_${OSVer}_${BuildVer}_Restore"
        if [ ! "$IPSW.ipsw" ]; then
            Log "iOS $OSVer IPSW cannot be found. Downloading IPSW..."
            curl -L $(cat $Firmware/$BuildVer/url) -o tmp/$IPSW.ipsw
            mv tmp/$IPSW.ipsw .
        fi
        Log "Verifying IPSW..."
        IPSWSHA1=$(cat $Firmware/$BuildVer/sha1sum)
        IPSWSHA1L=$(sha1sum "$IPSW.ipsw" | awk '{print $1}')
        [ $IPSWSHA1L != $IPSWSHA1 ] && Error "Verifying IPSW failed. Delete/replace the IPSW and run the script again"
        if [ ! $DFUManual ]; then
            Log "Extracting iBSS from IPSW..."
            mkdir -p saved/$ProductType 2>/dev/null
            unzip -o -j "$IPSW.ipsw" Firmware/dfu/$iBSS.dfu -d saved/$ProductType
        fi
    fi
    
    [ ! $DFUManual ] && kDFU
    
    Log "Extracting IPSW..."
    unzip -q "$IPSW.ipsw" -d "$IPSW/"
    if [ $A7Device == 1 ]; then
        Log "Preparing custom IPSW..."
        cp $IPSW/firmware/all_flash/$SEP .
        bspatch $IPSW/firmware/dfu/$iBSS.im4p $iBSS.im4p resources/patches/$iBSS.patch
        bspatch $IPSW/firmware/dfu/$iBEC.im4p $iBEC.im4p resources/patches/$iBEC.patch
        cp -f $iBSS.im4p $iBEC.im4p $IPSW/firmware/dfu
        #IPSWCustom="${ProductType}_${OSVer}_${BuildVer}_Custom.ipsw"
        #zip -0 IPSW/* $IPSWCustom
        Log "Entering PWNREC mode..."
        sudo irecovery -f $iBSS.im4p
        sleep 5
        sudo irecovery -f $iBEC.im4p
        sleep 5
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
            sudo resources/tools/futurerestore_$platform -t "$SHSH" -s $(ls *.im4p) -m $BuildManifest --no-baseband --use-pwndfu "$IPSWCustom"
        else
            sudo resources/tools/futurerestore_$platform -t "$SHSH" --no-baseband --use-pwndfu "$IPSW.ipsw"
        fi
    else
        if [ ! saved/$ProductType/*.bbfw ]; then
            Log "Downloading baseband..."
            resources/tools/pzb_$platform -g Firmware/$Baseband -o $Baseband $BasebandURL
            resources/tools/pzb_$platform -g BuildManifest.plist -o BuildManifest.plist $BasebandURL
            mkdir -p saved/$ProductType 2>/dev/null
            cp $(ls *.bbfw) BuildManifest.plist saved/$ProductType
        else
            cp saved/$ProductType/*.bbfw saved/$ProductType/BuildManifest.plist .
        fi
        BasebandSHA1L=$(sha1sum $(ls *.bbfw) | awk '{print $1}')
        if [ ! *.bbfw ] || [ $BasebandSHA1L != $BasebandSHA1 ]; then
            rm saved/$ProductType/*.bbfw saved/$ProductType/BuildManifest.plist
            echo "[Error] Downloading/verifying baseband failed."
            echo "Your device is still in kDFU mode and you may run the script again"
            echo "You can also continue and futurerestore can attempt to download the baseband again"
            echo "Proceeding to futurerestore in 10 seconds (Press Ctrl+C to cancel)"
            sleep 10
            Log "Proceeding to futurerestore..."
            if [ $A7Device == 1 ]; then
                sudo resources/tools/futurerestore_$platform -t "$SHSH" --latest-sep --latest-baseband --use-pwndfu "$IPSWCustom"
            else
                sudo resources/tools/futurerestore_$platform -t "$SHSH" --latest-baseband --use-pwndfu "$IPSW.ipsw"
            fi
        elif [ $A7Device == 1 ]; then
            Log "Proceeding to futurerestore..."
            sudo resources/tools/futurerestore_$platform -t "$SHSH" -s $(ls *.im4p) -m $BuildManifest -b $(ls *.bbfw) -p $BuildManifest --use-pwndfu "$IPSWCustom"
        else
            Log "Proceeding to futurerestore..."
            sudo resources/tools/futurerestore_$platform -t "$SHSH" -b $(ls *.bbfw) -p BuildManifest.plist --use-pwndfu "$IPSW.ipsw"
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
    
    if [[ $(which pacman) ]]; then
        # Arch Linux
        Log "Installing dependencies for Arch with pacman..."
        sudo pacman -Sy --noconfirm --needed bsdiff curl libpng12 libimobiledevice libzip openssh openssl-1.0 python2 python unzip usbmuxd usbutils
        git clone https://aur.archlinux.org/ifuse.git
        cd ifuse
        makepkg -sic --noconfirm
        
    elif [[ $VERSION_ID == "18.04" ]] || [[ $VERSION_ID == "20.04" ]]; then
        # Ubuntu Bionic, Focal
        Log "Running APT update..." 
        sudo apt update
        Log "Installing dependencies for Ubuntu $VERSION_ID with APT..."
        sudo apt -y install autoconf automake binutils bsdiff build-essential checkinstall curl git ifuse libimobiledevice-utils libreadline-dev libtool-bin libusb-1.0-0-dev libzip5 python2 python3 usbmuxd
        if [[ $VERSION_ID == "20.04" ]]; then
            URLlibpng12=http://ppa.launchpad.net/linuxuprising/libpng12/ubuntu/pool/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1.1+1~ppa0~focal_amd64.deb
            curl -L http://archive.ubuntu.com/ubuntu/pool/main/o/openssl1.0/libssl1.0.0_1.0.2n-1ubuntu5.3_amd64.deb -o libssl1.0.0.deb
            sudo dpkg -i libssl1.0.0.deb
        else
            URLlibpng12=http://mirrors.edge.kernel.org/ubuntu/pool/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1.1_amd64.deb
        fi
        curl -L $URLlibpng12 -o libpng12.deb
        sudo dpkg -i libpng12.deb
        sudo ln -sf /usr/lib/x86_64-linux-gnu/libimobiledevice.so.6 /usr/lib/x86_64-linux-gnu/libimobiledevice-1.0.so.6
        git clone https://github.com/libimobiledevice/libirecovery
        cd libirecovery
        ./autogen.sh
        sudo make install
        cd ..
        sudo rm -rf libirecovery
    
    elif [[ $(which dnf) ]]; then
        sudo dnf install -y bsdiff ifuse libimobiledevice-utils libpng12 libzip python2
        curl -L http://ftp.pbone.net/mirror/ftp.scientificlinux.org/linux/scientific/6.1/x86_64/os/Packages/openssl-1.0.0-10.el6.x86_64.rpm -o openssl-1.0.0.rpm
        rpm2cpio openssl-1.0.0.rpm | cpio -idmv
        sudo cp usr/lib64/libcrypto.so.1.0.0 usr/lib64/libssl.so.1.0.0 /usr/local/lib
        
    elif [[ $OSTYPE == "darwin"* ]]; then
        # macOS
        if [[ ! $(which brew) ]]; then
            Log "Homebrew is not detected/installed, installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
        fi
        Log "Installing dependencies for macOS with Homebrew..."
        brew uninstall --ignore-dependencies usbmuxd
        brew uninstall --ignore-dependencies libimobiledevice
        brew install --HEAD usbmuxd
        brew install --HEAD libimobiledevice
        brew install libzip lsusb python3
        brew cask install osxfuse
        brew install ifuse
        
    else
        Error "Distro not detected/supported by the install script." "See the repo README for OS versions/distros tested on"
    fi
    
    [[ $platform == linux ]] && sudo cp ../resources/lib/* /usr/local/lib
    Log "Install script done! Please run the script again to proceed"
}

function SaveExternal {
    if [[ ! $(ls resources/$1) 2>/dev/null ]]; then
        Log "Downloading $1..."
        curl -Ls https://github.com/LukeZGD/32bit-OTA-Downgrader/archive/$1.zip -o tmp/$1.zip
        unzip -q tmp/$1.zip -d tmp
        mkdir resources/$1
        mv tmp/32bit-OTA-Downgrader-$1/* resources/$1
    fi
}

function GetProductType {
    ProductType=$(resources/tools/igetnonce_$platform)
    if [ ! $ProductType ] && [ -e resources/ProductType ]; then
        read -p "[Input] Confirm ProductType $(cat resources/ProductType) (Y/n) " ConfirmPType
        if [ $ConfirmPType == n ] || [ $ConfirmPType == N ]; then
            rm -f resources/ProductType
            exit
        fi
    elif [ ! $ProductType ]; then
        read -p "[Input] Enter ProductType (eg. iPad2,1): " ProductType
    fi
}

function BasebandDetect {
    Firmware=resources/firmware/$ProductType
    BasebandURL=$(cat $Firmware/13G37/url 2>/dev/null) # iOS 9.3.6
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
    elif [ $ProductType == iPad4,2 ] || [ $ProductType == iPad4,3 ] ||
         [ $ProductType == iPad4,5 ] || [ $ProductType == iPad4,6 ] ||
         [ $ProductType == iPhone6,1 ] || [ $ProductType == iPhone6,2 ]; then
        BasebandURL=$(cat $Firmware/16G201/url) # iOS 12.4.8
        Baseband=Mav7Mav8-10.80.02.Release.bbfw
        BasebandSHA1=f5db17f72a78d807a791138cd5ca87d2f5e859f0
        A7Device=1
    elif [ $ProductType == iPad4,1 ] || [ $ProductType == iPad4,4 ]; then
        Baseband=0
        A7Device=1
    else # For Wi-Fi only devices
        Baseband=0
    fi
    SEP=sep-firmware
    if [ $ProductType == iPhone6,1 ]; then
        SEP=$SEP.n51.RELEASE.im4p
    elif [ $ProductType == iPhone6,2 ]; then
        SEP=$SEP.n53.RELEASE.im4p
    elif [ $ProductType == iPad4,1 ]; then
        SEP=$SEP.j71.RELEASE.im4p
    elif [ $ProductType == iPad4,2 ]; then
        SEP=$SEP.j72.RELEASE.im4p
    elif [ $ProductType == iPad4,3 ]; then
        SEP=$SEP.j73.RELEASE.im4p
    elif [ $ProductType == iPad4,4 ]; then
        SEP=$SEP.j85.RELEASE.im4p
    elif [ $ProductType == iPad4,5 ]; then
        SEP=$SEP.j86.RELEASE.im4p
    elif [ $ProductType == iPad4,6 ]; then
        SEP=$SEP.j87.RELEASE.im4p
    fi
}

Main
