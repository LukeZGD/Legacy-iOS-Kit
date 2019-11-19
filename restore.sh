#!/bin/bash

platform="linux"

iv_k93=781b9672a86ba1b41f8b7fa0af714c94
key_k93=db03d63a767b5211d644fccd3e85ef4d5704c94d7589e0fa9ca475a353d8734b

iv_k94=883c92ed915e4d2481570a062583495b
key_k94=ccfadf3732904885d38f963cce035d7e03b387b67212d526503c85773b58e52f

iv_k95=460116385cca6d5596221c58ae122669
key_k95=7852f1fd93d9d49ebea44021081e8f1dffa336d0d3e9517374f8be451dd92eb7

iv_k93a=976aa656929ac699fff36715de96876d
key_k93a=5fe5c47b5620c2b40b1ca2bd1764a92d568901a24e1caf8faf0cf0f84ae11b4e

iv_p101=b21abc8689b0dea8f6e613f9f970e241
key_p101=b9ed63e4a31f5d9d4d7dddc527e65fd31d1ea48c70204e6b44551c1e6dfc52b5

iv_p102=56231fd62c6296ed0c8c411bcef602e0
key_p102=cdb2142489e5e936fa8f3540bd036f62ed0f27ddb6fec96b9fbfec5a65bc5f17

iv_p103=fa39c596b6569e572d90f0820e4e4357
key_p103=34b359fcc729a0f0d2853e786a78b245ed36a9212c8296aaab95dc0401cf07de

iv_j1=c3ea87ed43788dfc3e268abdf1af27dd
key_j1=cd3dd7eee07b9ce8b180d1526632cf86dc7fef7d52352d06af354598ab9cf2ef

iv_j2=32fcd912cb9a472ef2a6db72596ae01c
key_j2=076720d5a07e8011bdda6f6eafaf4845b40a441615cd1d7c1a9cca438ce7db17

iv_j2a=e6b041970cd611c8a1561a4c210bc476
key_j2a=aec6a888d45bd26106ac620d7d4ec0c160ab80276deedc1b50ce8f5d99dcc9af

iv_p105=a5892a58c90b6d3fb0e0b20db95070d7
key_p105=75612774968009e3f85545ac0088d0d0bb9cb4e2c2970e8f88489be0b9dfe103

iv_p106=fba6d9aaec7237891c80390e6ffa88bf
key_p106=92909dca9bfdb9193131f9ad9b628b1a4971b1cbab52c0ddd114a6253fad96c0

iv_p107=1d99e780d96c32a25ca7e4b1c7fe14c0
key_p107=4e2c14927693d61e1da375e340061521c9376007163f6ab55afbe1a03b901fd3

iv_n78=e0175b03bc29817adc312638884e0898
key_n78=0a0e0aedc8171669c9af6a229930a395959df55dcd8a3ee1fe0f4c009007df3c

iv_n94=147cdef921ed14a5c10631c5e6e02d1e
key_n94=6ea1eb62a9f403ee212c1f6b3039df093963b46739c6093407190fe3d750c69c

iv_n41=bd0c8b039a819604a30f0d39adf88572
key_n41=baf05fe0282f78c18c2e3842be4f9021919d586b55594281f5b5abd0f6e61495

iv_n42=fdad2b7a35384fa2ffc7221213ca1082
key_n42=74cd68729b800a20b1f8e8a3cb5517024a09f074eaa05b099db530fb5783275e

clear
echo "******* 841-OTA-Downgrader *******"
echo "          - by LukeZGD            "
echo

HardwareModel=$(ideviceinfo | grep 'HardwareModel' | cut -c 16-)
HardwareModelLower=$(echo $HardwareModel | tr '[:upper:]' '[:lower:]' | sed 's/.\{2\}$//')
ProductType=$(ideviceinfo | grep 'ProductType' | cut -c 14-)
ProductVersion=$(ideviceinfo | grep 'ProductVersion' | cut -c 17-)
UniqueChipID=$(ideviceinfo | grep 'UniqueChipID' | cut -c 15-)
iBSS="iBSS.$HardwareModelLower.RELEASE"

if [ ! $HardwareModel ]
then
    echo "Please plug the device in before proceeding"
    echo
    exit
fi

echo "HardwareModel: $HardwareModel"
echo "ProductType: $ProductType"
echo "ProductVersion: $ProductVersion"
echo "UniqueChipID (ECID): $UniqueChipID"
echo "iBSS: $iBSS"
echo

IPSW="${ProductType}_8.4.1_12H321_Restore"

#if [ ! -e ${IPSW}.ipsw ]
if [  -e ${IPSW}.ipsw ]
then
    echo "iOS 8.4.1 IPSW is missing! Please put the IPSW on the same directory of this script"
    echo
    exit
fi

echo "Downloading tsschecker..."
mkdir tmp
wget -q "https://github.com/tihmstar/tsschecker/releases/download/v212/tsschecker_v212_mac_win_linux.zip" -O "tmp/tsschecker.zip"
echo "Extracting tsschecker..."
unzip -q tmp/tsschecker.zip -d tools/tsschecker/
chmod +x tools/tsschecker/tsschecker_$platform
echo

echo "Downloading futurerestore..."
wget -q "http://api.tihmstar.net/builds/futurerestore/futurerestore-latest.zip" -O "tmp/futurerestore.zip"
echo "Extracting futurerestore..."
unzip -q tmp/futurerestore.zip -d tools/futurerestore/
chmod +x tools/futurerestore/futurerestore_$platform
echo 

echo "Downloading ota.json..."
wget -q "https://api.ipsw.me/v2.1/ota.json/condensed" -O tmp/ota.json
echo "Copying ota.json to /tmp..."
cp tmp/ota.json /tmp
echo

echo "Downloading OTA Firmware..."
wget -q "https://api.ipsw.me/v4/ota/download/$ProductType/12H321?prerequisite=12H143" -O tmp/ota.zip
echo "Extracting BuildManifest.plist..."
unzip -q -j tmp/ota.zip AssetData/boot/BuildManifest.plist -d tmp/
echo

echo "Saving 8.4.1 blobs with tsschecker..."
env "LD_PRELOAD=libcurl.so.3" tools/tsschecker/tsschecker_$platform -d $ProductType -i 8.4.1 -o -s -e $UniqueChipID -m tmp/BuildManifest.plist > /dev/null 2>&1
echo

echo "Extracting 8.4.1 IPSW..."
unzip -q ${IPSW}.ipsw -d $IPSW/
echo

echo "Decrypting iBSS..."
iv=iv_$HardwareModelLower
key=key_$HardwareModelLower
echo "IV = ${!iv}"
echo "Key = ${!key}"
tools/xpwntool_$platform $IPSW/Firmware/dfu/$iBSS.dfu tmp/iBSS.dec -k ${!key} -iv ${!iv} -decrypt
echo

echo "Patching iBSS..."
bspatch tmp/iBSS.dec patches/$iBSS.patch tmp/pwnediBSS
echo

if [ ! $iOS10 ]
then
    kloader="kloader"
else
    kloader="kloader_hgsp"
fi

echo "Please enter Wi-Fi IP address of device for SSH connection:"
#read IPAddress
echo "Will now connect to device using SSH"
echo "Please enter root password when prompted (default is 'alpine')"
echo

echo "Copying stuff to device..."
scp tools/$kloader root@$IPAddress:/usr/bin
scp tmp/pwnediBSS root@$IPAddress:/
echo

echo "Entering pwnDFU mode..."
ssh root@$IPAddress "$kloader /pwnediBSS"
echo
