#!/bin/bash

function BasebandDetect {
    Firmware=resources/firmware/$ProductType
    BasebandURL=$(cat $Firmware/13G37/url 2>/dev/null)
    if [ $ProductType == iPad2,2 ]; then
        BasebandURL=$(cat $Firmware/13G36/url)
        Baseband=ICE3_04.12.09_BOOT_02.13.Release.bbfw
    elif [ $ProductType == iPad2,3 ]; then
        Baseband=Phoenix-3.6.03.Release.bbfw
    elif [ $ProductType == iPad2,6 ] || [ $ProductType == iPad2,7 ]; then
        Baseband=Mav5-11.80.00.Release.bbfw
    elif [ $ProductType == iPad3,2 ] || [ $ProductType == iPad3,3 ]; then
        Baseband=Mav4-6.7.00.Release.bbfw
    elif [ $ProductType == iPhone4,1 ]; then
        Baseband=Trek-6.7.00.Release.bbfw
    elif [ $ProductType == iPad3,5 ] || [ $ProductType == iPad3,6 ] ||
         [ $ProductType == iPhone5,1 ] || [ $ProductType == iPhone5,2 ]; then
        BasebandURL=$(cat $Firmware/14G61/url)
        Baseband=Mav5-11.80.00.Release.bbfw
    else # For Wi-Fi only devices
        Baseband=0
    fi
}

function Clean {
    # Clean up files (called on MainMenu and trap dependency)
    rm -rf iP*/ tmp/ $(ls ${UniqueChipID}_${ProductType}_${DowngradeVer}-*.shsh2 2>/dev/null) $(ls *.bbfw 2>/dev/null) BuildManifest.plist
}

function MainMenu {    
    if [ $(lsusb | grep -c '1227') == 1 ]; then
        read -p "[Input] Device in DFU mode detected. Is the device in kDFU mode? (y/N) " kDFUManual
        if [[ $kDFUManual == y ]] || [[ $kDFUManual == Y ]]; then
            read -p "[Input] Enter ProductType (eg. iPad2,1): " ProductType
            if [ $(which irecovery) ]; then
                # Get ECID with irecovery (optional)
                echo "[Log] Getting UniqueChipID (ECID) with irecovery..."
                UniqueChipID=$(sudo irecovery -q | grep 'ECID:' | cut -c 7-)
            else
                read -p "[Input] Enter UniqueChipID (ECID): " UniqueChipID
            fi
            BasebandDetect
            echo "[Log] Downgrading device $ProductType in kDFU mode..."
            Mode='Downgrade'
            SelectVersion
        else
            echo "[Error] Please put the device in normal mode and jailbroken before proceeding"
            exit
        fi
    elif [ ! $ProductType ]; then
        echo "[Error] Please plug the device in and trust this computer before proceeding"
        exit
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
    select opt in "Downgrade device" "Save OTA blobs" "Just put device in kDFU mode" "(Re-)Install Dependencies" "Exit"; do
        case $opt in
            "Downgrade device" ) Mode='Downgrade'; break;;
            "Save OTA blobs" ) Mode='SaveOTABlobs'; break;;
            "Just put device in kDFU mode" ) Mode='kDFU'; break;;
            "(Re-)Install Dependencies" ) InstallDependencies;;
            "Exit" ) exit;;
            *) MainMenu;;
        esac
    done
    SelectVersion
}

function SelectVersion {
    Selection=("iOS 8.4.1")
    if [[ $Mode == 'kDFU' ]]; then
        Select841
    elif [ $ProductType == iPad2,1 ] || [ $ProductType == iPad2,2 ] ||
         [ $ProductType == iPad2,3 ] || [ $ProductType == iPhone4,1 ]; then
        Selection+=("iOS 6.1.3")
    fi
    [[ $Mode == 'Downgrade' ]] && Selection+=("Other")
    Selection+=("Back")
    echo "[Input] Select iOS version:"
    select opt in "${Selection[@]}"; do
        case $opt in
            "iOS 8.4.1" ) Select841; break;;
            "iOS 6.1.3" ) Select613; break;;
            "Other" ) SelectOther; break;;
            "Back" ) MainMenu; break;;
            *) SelectVersion;;
        esac
    done
}

function Select841 {
    echo "iOS 8.4.1 $Mode"
    iBSS="iBSS.$HWModel.RELEASE"
    DowngradeVer="8.4.1"
    DowngradeBuildVer="12H321"
    Action
}

function Select613 {
    echo "iOS 6.1.3 $Mode"
    iBSS="iBSS.${HWModel}ap.RELEASE"
    DowngradeVer="6.1.3"
    DowngradeBuildVer="10B329"
    Action
}

function SelectOther {
    echo "Other $Mode"
    iBSS="iBSS.$HWModel.RELEASE"
    DowngradeBuildVer="12H321"
    NotOTA=1
    read -p "[Input] Path to IPSW (drag IPSW to terminal window): " IPSW
    IPSW="$(basename "$IPSW" .ipsw)"
    read -p "[Input] Path to SHSH (drag SHSH to terminal window): " SHSH
    Action
}

function Action {
    Firmware=$Firmware/$DowngradeBuildVer
    IV=$(cat $Firmware/iv)
    Key=$(cat $Firmware/key)
    
    if [[ $Mode == 'Downgrade' ]]; then
        Downgrade
    elif [[ $Mode == 'SaveOTABlobs' ]]; then
        SaveOTABlobs
    elif [[ $Mode == 'kDFU' ]]; then
        kDFU; exit
    fi
}

function SaveOTABlobs {
    BuildManifest="resources/manifests/BuildManifest_${ProductType}_${DowngradeVer}.plist"
    echo "[Log] Saving $DowngradeVer blobs with tsschecker..."
    env "LD_PRELOAD=libcurl.so.3" resources/tools/tsschecker_$platform -d $ProductType -i $DowngradeVer -o -s -e $UniqueChipID -m $BuildManifest
    SHSH=$(ls ${UniqueChipID}_${ProductType}_${DowngradeVer}-*.shsh2)
    if [ ! -e "$SHSH" ]; then
        echo "[Error] Saving $DowngradeVer blobs failed. Please run the script again"
        echo "It is also possible that $DowngradeVer for $ProductType is no longer signed"
        exit
    fi
    mkdir -p saved/shsh 2>/dev/null
    cp "$SHSH" saved/shsh
}

function kDFU {
    if [ ! -e saved/$ProductType/$iBSS.dfu ]; then
        # Downloading 8.4.1 iBSS for "other" downgrades
        # This is because this script only provides 8.4.1 iBSS IV and Keys
        echo "[Log] Downloading iBSS..."
        resources/tools/pzb_$platform -g Firmware/dfu/${iBSS}.dfu -o $iBSS.dfu $(cat $Firmware/url)
        mkdir -p saved/$ProductType 2>/dev/null
        mv $iBSS.dfu saved/$ProductType
    fi
    echo "[Log] Decrypting iBSS..."
    echo "IV = $IV"
    echo "Key = $Key"
    resources/tools/xpwntool_$platform saved/$ProductType/$iBSS.dfu tmp/iBSS.dec -k $Key -iv $IV -decrypt
    dd bs=64 skip=1 if=tmp/iBSS.dec of=tmp/iBSS.dec2
    echo "[Log] Patching iBSS..."
    bspatch tmp/iBSS.dec2 tmp/pwnediBSS resources/patches/$iBSS.patch
    
    # Regular kloader only works on iOS 6 to 9, so other versions are provided for iOS 5 and 10
    if [[ $VersionDetect == 1 ]]; then
        kloader='kloader_hgsp'
    elif [[ $VersionDetect == 5 ]]; then
        kloader='kloader5'
    else
        kloader='kloader'
    fi

    if [[ $VersionDetect == 1 ]]; then
        # SSH is unreliable/not working on iOS 10 devices, so ifuse+MTerminal is used instead
        # It's less convenient, but it should work every time
        if [ ! $(which ifuse) ]; then
            echo "[Error] ifuse not found. Please re-install dependencies and try again"
            echo "For macOS systems, install osxfuse and ifuse with brew"
            exit
        fi
        WifiAddr=$(ideviceinfo -s | grep 'WiFiAddress' | cut -c 14-)
        WifiAddrDecr=$(echo $(printf "%x\n" $(expr $(printf "%d\n" 0x$(echo "${WifiAddr}" | tr -d ':')) - 1)) | sed 's/\(..\)/\1:/g;s/:$//')
        echo '#!/bin/bash' > tmp/pwn.sh
        echo "nvram wifiaddr=$WifiAddrDecr
        chmod 755 kloader_hgsp
        ./kloader_hgsp pwnediBSS" >> tmp/pwn.sh
        echo "[Log] Mounting device with ifuse..."
        mkdir mount
        ifuse mount
        echo "[Log] Copying stuff to device..."
        cp "tmp/pwn.sh" "resources/tools/$kloader" "tmp/pwnediBSS" "mount/"
        echo "[Log] Unmounting device..."
        sudo umount mount
        echo
        echo "[Log] Open MTerminal and run these commands:"
        echo
        echo '$ su'
        echo "(enter root password, default is 'alpine')"
        echo "# cd Media"
        echo "# chmod +x pwn.sh"
        echo "# ./pwn.sh"
    else
        # SSH: Send kloader and pwnediBSS to device root and run kloader as root
        echo "Make sure SSH is installed and working on the device!"
        echo "Please enter Wi-Fi IP address of device for SSH connection"
        read -p "[Input] IP Address: " IPAddress
        echo "[Log] Coonecting to device via SSH... Please enter root password when prompted (default is 'alpine')"
        echo "[Log] Copying stuff to device..."
        scp resources/tools/$kloader tmp/pwnediBSS root@$IPAddress:/
        if [ $? == 1 ]; then
            echo "[Error] Cannot connect to device via SSH. Please check your ~/.ssh/known_hosts file and try again"
            exit
        fi
        echo "[Log] Entering kDFU mode..."
        ssh root@$IPAddress "chmod 755 /$kloader && /$kloader /pwnediBSS" &
    fi
    echo
    echo "Press home/power button once when screen goes black on the device"
    FindDFU
}

function FindDFU {
    echo "[Log] Finding device in DFU mode..."
    while [[ $DFUDevice != 1 ]]; do
        DFUDevice=$(lsusb | grep -c "1227")
        sleep 2
    done
    echo "[Log] Found device in DFU mode."
}

function Downgrade {    
    if [ ! $NotOTA ]; then
        SaveOTABlobs
        IPSW="${ProductType}_${DowngradeVer}_${DowngradeBuildVer}_Restore"
        if [ ! -e "$IPSW.ipsw" ]; then
            echo "[Log] iOS $DowngradeVer IPSW is missing, downloading IPSW..."
            curl -L $(cat $Firmware/url) -o tmp/$IPSW.ipsw
            mv tmp/$IPSW.ipsw .
        fi
        echo "[Log] Verifying IPSW..."
        SHA1IPSW=$(cat $Firmware/sha1sum)
        SHA1IPSWL=$(sha1sum "$IPSW.ipsw" | awk '{print $1}')
        if [ $SHA1IPSW != $SHA1IPSWL ]; then
            echo "[Error] SHA1 of IPSW does not match. Please run the script again"
            exit
        fi
        echo "[Log] Extracting iBSS from IPSW..."
        mkdir -p saved/$ProductType 2>/dev/null
        unzip -o -j "$IPSW.ipsw" Firmware/dfu/$iBSS.dfu -d saved/$ProductType
    fi
    
    [ ! $kDFUManual ] && kDFU
    
    echo "[Log] Extracting IPSW..."
    unzip -q "$IPSW.ipsw" -d "$IPSW/"
    
    echo "[Log] Preparing for futurerestore (starting local server)..."
    cd resources
    sudo bash -c "python3 -m http.server 80 &"
    cd ..
    
    if [ $Baseband == 0 ]; then
        echo "[Log] Device $ProductType has no baseband"
        echo "[Log] Proceeding to futurerestore..."
        sudo env "LD_PRELOAD=libcurl.so.3" resources/tools/futurerestore_$platform -t "$SHSH" --no-baseband --use-pwndfu "$IPSW.ipsw"
    else
        if [ ! -e saved/$ProductType/*.bbfw ]; then
            echo "[Log] Downloading baseband..."
            resources/tools/pzb_$platform -g Firmware/$Baseband -o $Baseband $BasebandURL
            resources/tools/pzb_$platform -g BuildManifest.plist -o BuildManifest.plist $BasebandURL
            mkdir -p saved/$ProductType 2>/dev/null
            cp $(ls *.bbfw) BuildManifest.plist saved/$ProductType
        else
            cp saved/$ProductType/*.bbfw saved/$ProductType/BuildManifest.plist .
        fi
        if [ ! -e *.bbfw ]; then
            echo "[Error] Downloading baseband failed!"
            echo "Your device is still in kDFU mode, you may run the script again"
            echo "If you continue, futurerestore can attempt to download the baseband again"
            read -p "[Input] Continue anyway? (y/N)" Continue
            if [[ $Continue == y ]] || [[ $Continue == Y ]]; then
                echo "[Log] Proceeding to futurerestore..."
                sudo env "LD_PRELOAD=libcurl.so.3" resources/tools/futurerestore_$platform -t "$SHSH" --latest-baseband --use-pwndfu "$IPSW.ipsw"
            else
                exit
            fi
        fi
        if [[ $Continue != y ]] && [[ $Continue != Y ]]; then
            echo "[Log] Proceeding to futurerestore..."
            sudo env "LD_PRELOAD=libcurl.so.3" resources/tools/futurerestore_$platform -t "$SHSH" -b $(ls *.bbfw) -p BuildManifest.plist --use-pwndfu "$IPSW.ipsw"
        fi
    fi
        
    echo
    echo "[Log] futurerestore done!"    
    echo "[Log] Stopping local server..."
    ps aux | awk '/python3/ {print "sudo kill -9 "$2" 2>/dev/null"}' | bash
    echo "[Log] Downgrade script done!"
    exit
}

function InstallDependencies {
    echo "Install Dependencies"

    . /etc/os-release 2>/dev/null
    if [[ $(which pacman) ]]; then
        Arch
    elif [[ $VERSION_ID == "16.04" ]]; then
        Ubuntu
    elif [[ $VERSION_ID == "18.04" ]]; then
        Ubuntu
        Ubuntu1804
    elif [[ $OSTYPE == "darwin"* ]]; then
        macOS
    else
        echo "[Error] Distro not detected/supported by install script."
        echo "See the repo README for Linux distros tested on"
        exit
    fi
    echo "[Log] Install script done! Please run the script again to proceed"
}

function Arch {
    echo "[Log] Installing dependencies for Arch with pacman..."
    sudo pacman -Sy --noconfirm bsdiff curl ifuse libcurl-compat libpng12 libzip openssh openssl-1.0 python unzip usbutils
    sudo pacman -S --noconfirm libimobiledevice usbmuxd
    sudo ln -sf /usr/lib/libzip.so.5 /usr/lib/libzip.so.4
}

function macOS {
    if [[ ! $(which brew) ]]; then
        echo "[Log] Homebrew is not detected/installed, installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
    fi
    echo "[Log] Installing dependencies for macOS with Homebrew..."
    brew uninstall --ignore-dependencies usbmuxd
    brew uninstall --ignore-dependencies libimobiledevice
    brew install --HEAD usbmuxd
    brew install --HEAD libimobiledevice
    brew install libzip lsusb
    brew cask install osxfuse
    brew install ifuse
}

function Ubuntu {
    echo "[Log] Running APT update..." 
    sudo apt update
    echo "[Log] Installing dependencies for Ubuntu with APT..."
    sudo apt -y install bsdiff curl ifuse libimobiledevice-utils libzip4 python3 usbmuxd
}

function Ubuntu1804 {
    echo "[Log] Installing dependencies for Ubuntu 18.04 with APT..."
    sudo apt -y install binutils
    mkdir tmp
    cd tmp
    apt download -o=dir::cache=. libcurl3
    ar x libcurl3* data.tar.xz
    tar xf data.tar.xz
    sudo cp usr/lib/x86_64-linux-gnu/libcurl.so.4.* /usr/lib/libcurl.so.3
    curl -L http://mirrors.edge.kernel.org/ubuntu/pool/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1.1_amd64.deb -o libpng12.deb
    sudo dpkg -i libpng12.deb
    cd ..
}

# --- MAIN SCRIPT STARTS HERE ---

trap 'Clean; exit' INT TERM EXIT
clear
echo "******* 32bit-OTA-Downgrader *******"
echo "    Downgrade script by LukeZGD     "
echo

if [[ $OSTYPE == "linux-gnu" ]]; then
    platform='linux'
elif [[ $OSTYPE == "darwin"* ]]; then
    platform='macos'
else
    echo "[Error] OSTYPE unknown/not supported"
    echo "Supports Linux and macOS only"
    exit
fi
if [[ ! $(ping -c1 google.com 2>/dev/null) ]]; then
    echo "[Error] Please check your Internet connection before proceeding"
    exit
fi
if [[ $(uname -m) != 'x86_64' ]]; then
    echo "[Error] Only x86_64 distributions are supported. Use a 64-bit distro and try again"
    exit
fi

HWModel=$(ideviceinfo -s | grep 'HardwareModel' | cut -c 16- | tr '[:upper:]' '[:lower:]' | sed 's/.\{2\}$//')
ProductType=$(ideviceinfo -s | grep 'ProductType' | cut -c 14-)
[ ! $ProductType ] && ProductType=$(ideviceinfo | grep 'ProductType' | cut -c 14-)
ProductVer=$(ideviceinfo -s | grep 'ProductVer' | cut -c 17-)
VersionDetect=$(echo $ProductVer | cut -c 1)
UniqueChipID=$(ideviceinfo -s | grep 'UniqueChipID' | cut -c 15-)

if [ ! $(which bspatch) ] || [ ! $(which ideviceinfo) ] || [ ! $(which lsusb) ] || [ ! $(which ssh) ] || [ ! $(which python3) ]; then
    InstallDependencies
else
    chmod +x resources/tools/*
    Clean
    mkdir tmp
    rm -rf resources/firmware
    curl -Ls https://github.com/LukeZGD/32bit-OTA-Downgrader/archive/firmware.zip -o tmp/firmware.zip
    unzip -q tmp/firmware.zip -d tmp
    mkdir resources/firmware
    mv tmp/32bit-OTA-Downgrader-firmware/* resources/firmware
    MainMenu
fi
