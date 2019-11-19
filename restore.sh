#!/bin/bash
clear

echo "******* 841-OTA-Downgrader *******"
echo "          - by LukeZGD            "
echo

HardwareModel=$(ideviceinfo | grep 'HardwareModel' | cut -c 16-)
HardwareModelLower=$(echo $HardwareModel | tr '[:upper:]' '[:lower:]' | sed 's/.\{2\}$//')
ProductType=$(ideviceinfo | grep 'ProductType' | cut -c 14-)

if [ ! $HardwareModel ]
then
    echo "Please plug in the device before proceeding"
    echo
    exit
fi

echo "HardwareModel = $HardwareModel"
echo "ProductType = $ProductType"
echo "HardwareModelLower = $HardwareModelLower"
echo

IPSW="${HardwareModel}_8.4.1_12H321_Restore.ipsw"

if [  -e $IPSW ]
then
    echo "iOS 8.4.1 IPSW is missing! Please put the IPSW on the same directory of this script"
    echo
    exit
fi

echo "Downloading kloader..."
wget -q "https://github.com/axi0mX/ios-kexec-utils/raw/master/kloader"
