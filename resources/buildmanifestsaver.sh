#!/bin/bash

devices=(iPhone4,1 iPhone5,1 iPhone5,2
iPad2,1 iPad2,2 iPad2,3 iPad2,4 iPad2,5 iPad2,6 iPad2,7
iPad3,1 iPad3,2 iPad3,3 iPad3,4 iPad3,5 iPad3,6 iPod5,1
)
devices613=(iPhone4,1 iPad2,1 iPad2,2 iPad2,3)

echo "32bit-OTA-Downgrader BuildManifest and Firmware Keys Saver"
echo "- by LukeZGD"
echo "Depends on partialZipBrowser! https://github.com/tihmstar/partialZipBrowser"

for ProductType in "${devices[@]}"
do
    dllink=$(curl -I -Ls -o /dev/null -w %{url_effective} https://api.ipsw.me/v4/ota/download/${ProductType}/12H321?prerequisite=12H143)
    pzb -g AssetData/boot/BuildManifest.plist -o manifests/BuildManifest_$ProductType.plist $dllink
    mkdir -p firmware/$ProductType/12H321
    curl -L https://firmware-keys.ipsw.me/firmware/$ProductType/12H321 -o firmware/$ProductType/12H321/index.html
done

for ProductType in "${devices613[@]}"
do
    dllink=$(curl -I -Ls -o /dev/null -w %{url_effective} https://api.ipsw.me/v4/ota/download/${ProductType}/10B329?prerequisite=10B146)
    pzb -g AssetData/boot/BuildManifest.plist -o manifests/BuildManifest613_$ProductType.plist $dllink
    mkdir -p firmware/$ProductType/10B329
    curl -L https://firmware-keys.ipsw.me/firmware/$ProductType/10B329 -o firmware/$ProductType/10B329/index.html
done
