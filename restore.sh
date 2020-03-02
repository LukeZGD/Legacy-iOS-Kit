#!/bin/bash

iv_k93=781b9672a86ba1b41f8b7fa0af714c94
key_k93=bbd7bf676dbcc6ba93c76d496b7af39ae7772eaaad2ec9fb71dc1fd004827784

iv_k94=883c92ed915e4d2481570a062583495b
key_k94=ccfadf3732904885d38f963cce035d7e03b387b67212d526503c85773b58e52f

iv_k95=460116385cca6d5596221c58ae122669
key_k95=7852f1fd93d9d49ebea44021081e8f1dffa336d0d3e9517374f8be451dd92eb7

iv_k93a=976aa656929ac699fff36715de96876d
key_k93a=5fe5c47b5620c2b40b1ca2bd1764a92d568901a24e1caf8faf0cf0f84ae11b4e

iv_p105=b21abc8689b0dea8f6e613f9f970e241
key_p105=b9ed63e4a31f5d9d4d7dddc527e65fd31d1ea48c70204e6b44551c1e6dfc52b5

iv_p106=56231fd62c6296ed0c8c411bcef602e0
key_p106=cdb2142489e5e936fa8f3540bd036f62ed0f27ddb6fec96b9fbfec5a65bc5f17

iv_p107=fa39c596b6569e572d90f0820e4e4357
key_p107=34b359fcc729a0f0d2853e786a78b245ed36a9212c8296aaab95dc0401cf07de

iv_j1=c3ea87ed43788dfc3e268abdf1af27dd
key_j1=cd3dd7eee07b9ce8b180d1526632cf86dc7fef7d52352d06af354598ab9cf2ef

iv_j2=32fcd912cb9a472ef2a6db72596ae01c
key_j2=076720d5a07e8011bdda6f6eafaf4845b40a441615cd1d7c1a9cca438ce7db17

iv_j2a=e6b041970cd611c8a1561a4c210bc476
key_j2a=aec6a888d45bd26106ac620d7d4ec0c160ab80276deedc1b50ce8f5d99dcc9af

iv_p101=a5892a58c90b6d3fb0e0b20db95070d7
key_p101=75612774968009e3f85545ac0088d0d0bb9cb4e2c2970e8f88489be0b9dfe103

iv_p102=fba6d9aaec7237891c80390e6ffa88bf
key_p102=92909dca9bfdb9193131f9ad9b628b1a4971b1cbab52c0ddd114a6253fad96c0

iv_p103=1d99e780d96c32a25ca7e4b1c7fe14c0
key_p103=4e2c14927693d61e1da375e340061521c9376007163f6ab55afbe1a03b901fd3

iv_n78=e0175b03bc29817adc312638884e0898
key_n78=0a0e0aedc8171669c9af6a229930a395959df55dcd8a3ee1fe0f4c009007df3c

iv_n94=147cdef921ed14a5c10631c5e6e02d1e
key_n94=6ea1eb62a9f403ee212c1f6b3039df093963b46739c6093407190fe3d750c69c

iv_n41=bd0c8b039a819604a30f0d39adf88572
key_n41=baf05fe0282f78c18c2e3842be4f9021919d586b55594281f5b5abd0f6e61495

iv_n42=fdad2b7a35384fa2ffc7221213ca1082
key_n42=74cd68729b800a20b1f8e8a3cb5517024a09f074eaa05b099db530fb5783275e

iv_n48=dbecd5f265e031835584e6bfbdb4c47f
key_n48=248f86d983626b75d26718fa52732eca64466ab73df048f278e034a272041f7e

iv_n49=039241f2b0212bb7c7b62ab4deec263f
key_n49=d0b49d366469ae2b1580d7d31b1bcf783d835e4fac13cfe9f9a160fa95010ac4

iv_k93_613=b69f753dccd09c9b98d345ec73bbf044
key_k93_613=6e4cce9ea6f2ec346cba0b279beab1b43e44a0680f1fde789a00f66a1e68ffab

iv_k94_613=bc3c9f168d7fb86aa219b7ad8039584b
key_k94_613=b1bd1dc5e6076054392be054d50711ae70e8fcf31a47899fb90ab0ff3111b687

iv_k95_613=56f964ee19bfd31f06e43e9d8fe93902
key_k95_613=0bb841b8f1922ae73d85ed9ed0d7a3583a10af909787857c15af2691b39bba30

iv_n94_613=d3fe01e99bd0967e80dccfc0739f93d5
key_n94_613=35343d5139e0313c81ee59dbae292da26e739ed75b3da5db9da7d4d26046498c

function Downgrade841 {
    iBSS="iBSS.$HardwareModelLower.RELEASE"
    DowngradeVersion="8.4.1"
    DowngradeBuildVer="12H321"
    BuildManifest="resources/manifests/BuildManifest_${ProductType}.plist"
    iv=iv_$HardwareModelLower
    key=key_$HardwareModelLower
    Downgrade
}

function Downgrade613 {
    if [ $ProductType == iPad2,1 ] || [ $ProductType == iPad2,2 ] || [ $ProductType == iPad2,3 ] || [ $ProductType == iPhone4,1 ]; then
        iBSS="iBSS.${HardwareModelLower}ap.RELEASE"
        DowngradeVersion="6.1.3"
        DowngradeBuildVer="10B329"
        BuildManifest="resources/manifests/BuildManifest613_${ProductType}.plist"
        iv=iv_${HardwareModelLower}_613
        key=key_${HardwareModelLower}_613
        Downgrade
    else
        echo "Your device does not support downgrading to 6.1.3 OTA"
    fi
}

function SaveOTABlobs {
    if [ ! -e ota.json ]; then
        echo "Downloading ota.json..."
        curl -L -# "https://api.ipsw.me/v2.1/ota.json/condensed" -o "ota.json"
    fi
    
    echo 'Copying ota.json to tmp...'
    if [ $platform == macos ]; then
        cp ota.json $TMPDIR
    else
        cp ota.json /tmp
    fi
    echo
    
    if [ ! -e /tmp/ota.json ] && [ ! -e $TMPDIR/ota.json ]; then
        echo "Download ota.json failed. Please run the script again"
        rm -rf tmp/ 
        exit
    fi

    echo "Extracting BuildManifest.plist..."
    echo
    if [ ! -e $BuildManifest ]; then
        echo "Download/extract BuildManifest.plist failed. Please run the script again"
        rm -rf tmp/
        exit
    fi

    echo "Saving $DowngradeVersion blobs with tsschecker..."
    env "LD_PRELOAD=libcurl.so.3" resources/tools/tsschecker_$platform -d $ProductType -i $DowngradeVersion -o -s -e $UniqueChipID -m tmp/$BuildManifest
    echo
    SHSH=$(ls *.shsh2)
    if [ ! -e $SHSH ]; then
        echo "Saving $DowngradeVersion blobs failed. Please run the script again"
        rm -rf tmp/
        exit
    fi
}

function Downgrade {
    IPSW="${ProductType}_${DowngradeVersion}_${DowngradeBuildVer}_Restore"
    
    if [ ! -e ${IPSW}.ipsw ]; then
        echo "iOS $DowngradeVersion IPSW is missing! Please put the IPSW on the same directory of this script"
        exit
    fi
    
    if [ ! $NotOTADowngrade ]; then
        SaveOTABlobs
    else
        echo "Please provide the path and name to the SHSH blob:"
        read SHSH
    fi
    
    echo "Extracting $DowngradeVersion IPSW..."
    unzip -q ${IPSW}.ipsw -d "$IPSW/"
    cp $IPSW/Firmware/dfu/$iBSS.dfu tmp/
    echo
    
    pwnDFU
    
    echo "Preparing for futurerestore..."
    cd resources
    sudo python3 -m http.server 80
    pythonPID=$!
    cd ..
    
    echo "Will now proceed to futurerestore..."
    echo

    while [[ $ScriptDone != 1 ]]; do
        if [[ ! $NoBaseband ]]; then
            sudo env "LD_PRELOAD=libcurl.so.3" resources/tools/futurerestore_$platform -t $SHSH --latest-baseband --use-pwndfu ${IPSW}.ipsw
        else
            echo "Detected device has no baseband"
            sudo env "LD_PRELOAD=libcurl.so.3" resources/tools/futurerestore_$platform -t $SHSH --no-baseband --use-pwndfu ${IPSW}.ipsw
        fi
        
        echo
        echo "futurerestore done!"
        echo "If futurerestore failed to download baseband or for some reason, you can choose to retry"
        echo "Retry? (y/n)"
        read retry
        if [ retry != y ] && [ retry != Y ]; then
            ScriptDone=1
        fi
    done
    
    kill $pythonPID    
    echo "Downgrade script done!"
    exit
}

function pwnDFUSelf {
    DowngradeVersion="8.4.1"
    IPSW="${ProductType}_8.4.1_12H321_Restore"
    iBSS="iBSS.$HardwareModelLower.RELEASE"
    iv=iv_$HardwareModelLower
    key=key_$HardwareModelLower
    if [ ! -e ${IPSW}.ipsw ]; then
        echo "Please provide an iOS 8.4.1 IPSW for your device to get to pwnDFU mode"
    else
        echo "Extracting iBSS from IPSW..."
        unzip -j ${IPSW}.ipsw Firmware/dfu/$iBSS.dfu -d "tmp/"
        pwnDFU
    fi
}

function pwnDFU {
    echo "Decrypting iBSS..."
    echo "IV = ${!iv}"
    echo "Key = ${!key}"
    resources/tools/xpwntool_$platform "tmp/${iBSS}.dfu" tmp/iBSS.dec -k ${!key} -iv ${!iv} -decrypt
    dd bs=64 skip=1 if=tmp/iBSS.dec of=tmp/iBSS.dec2
    echo

    echo "Patching iBSS..."
    bspatch tmp/iBSS.dec2 tmp/pwnediBSS resources/patches/$iBSS.patch
    echo

    if [[ $VersionDetect == 1 ]]; then
        kloader="kloader_hgsp"
    elif [[ $VersionDetect == 5 ]]; then
        kloader="kloader5"
    else
        kloader="kloader"
    fi

    if [[ $VersionDetect == 1 ]]; then
        WifiAddr=$(ideviceinfo -s | grep 'WiFiAddress' | cut -c 14-)
        WifiAddrDecr=$(echo $(printf "%x\n" $(expr $(printf "%d\n" 0x$(echo "${WifiAddr}" | tr -d ':')) - 1)) | sed 's/\(..\)/\1:/g;s/:$//')
        echo '#!/bin/bash' > tmp/pwn.sh
        echo "nvram wifiaddr=$WifiAddrDecr
        chmod 755 kloader_hgsp
        ./kloader_hgsp pwnediBSS" >> tmp/pwn.sh
        mkdir tmp/mountdir
        echo "Mounting device using ifuse..."
        ifuse tmp/mountdir
        echo "Copying stuff to device..."
        cp "tmp/pwn.sh" "resources/tools/$kloader" "tmp/pwnediBSS" "tmp/mountdir/"
        echo "Unmounting device..."
        sudo umount tmp/mountdir
        #rm -rf tmp/mountdir
        echo
        echo "Enter MTerminal and run these commands:"
        echo
        echo '$ su'
        echo "(enter root password, default is 'alpine')"
        echo "# cd Media"
        echo "# chmod +x pwn.sh"
        echo "# ./pwn.sh"
    else
        echo "Make sure SSH is installed and working on the device!"
        echo "Please enter Wi-Fi IP address of device for SSH connection:"
        read IPAddress
        echo "Will now connect to device using SSH"
        echo "Please enter root password when prompted (default is 'alpine')"
        echo
        echo "Copying stuff to device..."
        scp resources/tools/$kloader tmp/pwnediBSS root@$IPAddress:/
        echo
        echo "Entering pwnDFU mode..."
        echo "Try using tools like kDFUApp if the script fails to put device to pwnDFU"
        ssh root@$IPAddress "chmod 755 /$kloader && /$kloader /pwnediBSS" &
    fi
    echo
    echo "Press home/power button once when screen goes black on the device"
    FindDFU
}

function FindDFU {
    echo "Finding device in DFU mode..."
    while [[ $DFUDevice != 1 ]]; do
        DFUDevice=$(lsusb | grep -c "1227")
        sleep 2
    done
    echo "Found device in DFU mode."
    echo
}

function MainMenu {
    rm -rf iP*/ tmp/ $(ls *.shsh2 2>/dev/null)
    mkdir tmp
    
    if [ ! $ProductType ]
    then
        echo "Please plug the device in and trust this computer before proceeding"
        exit
    elif [ $ProductType == iPad2,1 ] || [ $ProductType == iPad2,4 ] || [ $ProductType == iPad2,5 ] || [ $ProductType == iPad3,1 ] || [ $ProductType == iPad3,4 ] || [ $ProductType == iPod5,1 ]
    then
        NoBaseband=1
    fi
	
    echo "Main Menu"
    echo
    echo "HardwareModel: $HardwareModel"
    echo "ProductType: $ProductType"
    echo "ProductVersion: $ProductVersion"
    echo "UniqueChipID (ECID): $UniqueChipID"
    echo
    select opt in "Downgrade device to iOS 8.4.1" "Downgrade device to iOS 6.1.3" "Just put device in pwnDFU mode" "(Re-)Install Dependencies" "Exit"; do
    case $opt in
        "Downgrade device to iOS 8.4.1" ) Downgrade841; break;;
        "Downgrade device to iOS 6.1.3" ) Downgrade613; break;;
        "Just put device in pwnDFU mode" ) pwnDFUSelf; break;;
        "(Re-)Install Dependencies" ) InstallDependencies; break;;
        "Exit" ) exit;;
        *) MainMenu;;
    esac
done
}

function InstallDependencies {
    echo "Install Dependencies"

    . /etc/os-release 2> /dev/null
    if [[ $(which pacman) ]] || [[ $NAME == "Arch Linux" ]]; then
        Arch
    elif [[ $NAME == "Ubuntu" ]] && [[ $VERSION_ID == "16.04" ]]; then
        Ubuntu
    elif [[ $(which apt) ]] || [[ $NAME == "Ubuntu" ]] && [[ $VERSION_ID == "18.04" ]]; then
        Ubuntu
        Ubuntu1804
    elif [[ $OSTYPE == "darwin"* ]]; then
        macOS
    else
        echo "Distro not detected/supported. Please select manually"
        select opt in "Ubuntu Xenial" "Ubuntu Bionic" "Arch Linux" "macOS"; do
        case $opt in
            "Ubuntu Xenial" ) Ubuntu; break;;
            "Ubuntu Bionic" ) Ubuntu; Ubuntu1804; break;;
            "Arch Linux" ) Arch; break;;
            "macOS" ) macOS; break;;
        esac
    done
    fi
    echo "Install script done! Please run the script again to proceed"
}

function Arch {
    sudo pacman -Sy --noconfirm bsdiff curl ifuse libcurl-compat libpng12 libzip openssh openssl-1.0 python unzip usbutils
    sudo pacman -S --noconfirm libimobiledevice usbmuxd
    sudo ln -sf /usr/lib/libzip.so.5 /usr/lib/libzip.so.4
}

function macOS {
    if [[ ! $(which brew) ]]; then
        xcode-select --install
        /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    fi
    brew uninstall --ignore-dependencies usbmuxd
    brew uninstall --ignore-dependencies libimobiledevice
    brew install --HEAD usbmuxd
    brew install --HEAD libimobiledevice
    brew install libzip openssl lsusb ifuse python3
}

function Ubuntu {
    sudo apt update
    sudo apt -y install bsdiff curl ifuse libimobiledevice-utils libzip4 python3 usbmuxd
}

function Ubuntu1804 {
    if [ $(uname -m) == 'x86_64' ]; then
        mtype='amd64'
    else
        mtype='i386'
    fi
    sudo apt -y install binutils
    mkdir tmp
    cd tmp
    apt download -o=dir::cache=. libcurl3
    ar x libcurl3* data.tar.xz
    tar xf data.tar.xz
    sudo cp usr/lib/${mtype}-linux-gnu/libcurl.so.4.* /usr/lib/libcurl.so.3
    curl -L -# http://mirrors.edge.kernel.org/ubuntu/pool/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1.1_${mtype}.deb -o libpng12.deb
    sudo dpkg -i libpng12.deb
    cd ..
    rm -rf tmp
}

# ----------------

clear
echo "******* 32bit-OTA-Downgrader *******"
echo "           - by LukeZGD             "
echo

if [[ $OSTYPE == "linux-gnu" ]]; then
    platform="linux"
elif [[ $OSTYPE == "darwin"* ]]; then
    platform="macos"
else
    echo "OSTYPE unknown/not supported, sorry!"
	echo "Supports macOS and Linux only"
    exit
fi

HardwareModel=$(ideviceinfo -s | grep 'HardwareModel' | cut -c 16-)
HardwareModelLower=$(echo $HardwareModel | tr '[:upper:]' '[:lower:]' | sed 's/.\{2\}$//')
ProductType=$(ideviceinfo -s | grep 'ProductType' | cut -c 14-)
[ ! $ProductType ] && ProductType=$(ideviceinfo | grep 'ProductType' | cut -c 14-)
ProductVersion=$(ideviceinfo -s | grep 'ProductVersion' | cut -c 17-)
VersionDetect=$(echo $ProductVersion | cut -c 1)
UniqueChipID=$(ideviceinfo -s | grep 'UniqueChipID' | cut -c 15-)

if [ ! $(which bspatch) ] || [ ! $(which ideviceinfo) ] || [ ! $(which ifuse) ] || [ ! $(which lsusb) ] || [ ! $(which ssh) ]
then
    InstallDependencies
else
    chmod +x resources/tools/*
    MainMenu
fi
