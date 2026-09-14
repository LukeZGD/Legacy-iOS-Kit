#!/usr/bin/env bash

set -ex

mkdir -p linux/aarch64/lib linux/x86_64/lib

curl -LO https://github.com/LukeZGD/a6meowing/releases/download/latest/a6meowing_linux-aarch64.zip
curl -LO https://github.com/LukeZGD/a6meowing/releases/download/latest/a6meowing_linux-x86_64.zip
unzip a6meowing_linux-aarch64.zip
mv a6meowing linux/aarch64/
unzip a6meowing_linux-x86_64.zip
mv a6meowing linux/x86_64/
rm -rf *.zip

curl -LO https://github.com/agalwood/Motrix/raw/refs/heads/master/extra/linux/arm64/engine/aria2c
mv aria2c linux/aarch64/
curl -LO https://github.com/agalwood/Motrix/raw/refs/heads/master/extra/linux/x64/engine/aria2c
mv aria2c linux/x86_64/

curl -LO https://github.com/LukeZGD/bsdiff/releases/download/latest/bsdiff_linux-aarch64.zip
unzip bsdiff_linux-aarch64.zip
mv output/bspatch linux/aarch64/
rm output/bsdiff
curl -LO https://github.com/LukeZGD/bsdiff/releases/download/latest/bsdiff_linux-x86_64.zip
unzip bsdiff_linux-x86_64.zip
mv output/bspatch linux/x86_64/
rm -rf output *.zip

curl -LO https://github.com/LukeZGD/darkhttpd/releases/download/latest/darkhttpd_linux-aarch64.zip
curl -LO https://github.com/LukeZGD/darkhttpd/releases/download/latest/darkhttpd_linux-x86_64.zip
unzip darkhttpd_linux-aarch64.zip
mv darkhttpd linux/aarch64/
unzip darkhttpd_linux-x86_64.zip
mv darkhttpd linux/x86_64/
rm -rf *.zip

curl -LO https://github.com/LukeZGD/daibutsuCFW/releases/download/latest/xpwn_linux-aarch64.zip
curl -LO https://github.com/LukeZGD/daibutsuCFW/releases/download/latest/xpwn_linux-x86_64.zip
unzip xpwn_linux-aarch64.zip
mv bin/xpwntool bin/hfsplus bin/ipsw bin/dmg bin/ticket linux/aarch64/
rm -rf bin
unzip xpwn_linux-x86_64.zip
mv bin/xpwntool bin/hfsplus bin/ipsw bin/dmg bin/ticket linux/x86_64/
rm -rf bin *.zip

curl -LO https://github.com/LukeZGD/futurerestore/releases/download/latest/futurerestore_new_linux-aarch64.zip
unzip futurerestore_new_linux-aarch64.zip
mv bin/futurerestore_new linux/aarch64/
rm -rf bin *.zip

curl -LO https://github.com/LukeZGD/futurerestore/releases/download/latest/futurerestore_old_linux-aarch64.zip
curl -LO https://github.com/LukeZGD/futurerestore/releases/download/latest/futurerestore_old_linux-x86_64.zip
unzip futurerestore_old_linux-aarch64.zip
mv bin/futurerestore_old linux/aarch64/
rm -rf bin
unzip futurerestore_old_linux-x86_64.zip
mv bin/futurerestore_old linux/x86_64/
rm -rf bin *.zip

curl -LO https://github.com/LukeZGD/gaster/releases/download/latest/gaster-Linux-aarch64.zip
curl -LO https://github.com/LukeZGD/gaster/releases/download/latest/gaster-Linux-x86_64.zip
unzip gaster-Linux-aarch64.zip
mv gaster linux/aarch64/
unzip gaster-Linux-x86_64.zip
mv gaster linux/x86_64/
rm -rf *.zip

curl -LO https://github.com/g1lbertJB/g1lbertJB/releases/download/v1.1.3/g1lbertJB-linux-aarch64-v1.1.3.zip
curl -LO https://github.com/g1lbertJB/g1lbertJB/releases/download/v1.1.3/g1lbertJB-linux-x86_64-v1.1.3.zip
mkdir tmp
unzip g1lbertJB-linux-aarch64-v1.1.3.zip -d tmp
mv tmp/gilbertjb tmp/usbmuxd linux/aarch64/
rm -rf tmp/*
unzip g1lbertJB-linux-x86_64-v1.1.3.zip -d tmp
mv tmp/gilbertjb tmp/usbmuxd linux/x86_64/
rm -rf tmp *.zip

curl -LO https://github.com/LukeZGD/iBoot32Patcher/releases/download/latest/iBoot32Patcher_linux-aarch64.zip
curl -LO https://github.com/LukeZGD/iBoot32Patcher/releases/download/latest/iBoot32Patcher_linux-x86_64.zip
unzip iBoot32Patcher_linux-aarch64.zip
mv iBoot32Patcher linux/aarch64/
unzip iBoot32Patcher_linux-x86_64.zip
mv iBoot32Patcher linux/x86_64/
rm -rf *.zip

curl -LO https://github.com/LukeZGD/ibootim/releases/download/latest/ibootim_linux-aarch64.zip
curl -LO https://github.com/LukeZGD/ibootim/releases/download/latest/ibootim_linux-x86_64.zip
unzip ibootim_linux-aarch64.zip
mv ibootim linux/aarch64/
unzip ibootim_linux-x86_64.zip
mv ibootim linux/x86_64/
rm -rf *.zip

curl -LO https://github.com/LukeZGD/idevicerestore/releases/download/latest/libimobiledevice_linux-aarch64.zip
curl -LO https://github.com/LukeZGD/idevicerestore/releases/download/latest/libimobiledevice_linux-x86_64.zip
unzip libimobiledevice_linux-aarch64.zip
mv bin/ideviceactivation bin/idevicebackup2 bin/idevicediagnostics bin/ideviceenterrecovery bin/ideviceinfo bin/ideviceinstaller bin/idevicepair bin/idevicerestore bin/idevicesyslog bin/inetcat bin/iproxy bin/irecovery bin/plistutil bin/lib linux/aarch64/
rm -rf bin
unzip libimobiledevice_linux-x86_64.zip
mv bin/ideviceactivation bin/idevicebackup2 bin/idevicediagnostics bin/ideviceenterrecovery bin/ideviceinfo bin/ideviceinstaller bin/idevicepair bin/idevicerestore bin/idevicesyslog bin/inetcat bin/iproxy bin/irecovery bin/plistutil bin/lib linux/x86_64/
rm -rf bin *.zip

curl -LO https://github.com/LukeZGD/ios-kexec-utils/releases/download/latest/img3maker_linux-aarch64.zip
curl -LO https://github.com/LukeZGD/ios-kexec-utils/releases/download/latest/img3maker_linux-x86_64.zip
unzip img3maker_linux-aarch64.zip
mv img3maker linux/aarch64/
unzip img3maker_linux-x86_64.zip
mv img3maker linux/x86_64/
rm -rf *.zip

curl -LO https://github.com/LukeZGD/img4lib/releases/download/latest/img4lib_linux-aarch64.zip
curl -LO https://github.com/LukeZGD/img4lib/releases/download/latest/img4lib_linux-x86_64.zip
unzip img4lib_linux-aarch64.zip
mv img4 linux/aarch64/
rm -rf libimg4.a
unzip img4lib_linux-x86_64.zip
mv img4 linux/x86_64/
rm -rf libimg4.a *.zip

curl -LO https://github.com/LukeZGD/img4tool/releases/download/latest/img4tool_linux-aarch64.zip
curl -LO https://github.com/LukeZGD/img4tool/releases/download/latest/img4tool_linux-x86_64.zip
unzip img4tool_linux-aarch64.zip
mv img4tool/img4tool linux/aarch64/
unzip img4tool_linux-x86_64.zip
mv img4tool/img4tool linux/x86_64/
rm -rf img4tool *.zip

curl -LO https://github.com/LukeZGD/irecovery/releases/download/latest/irecovery_linux-aarch64.zip
curl -LO https://github.com/LukeZGD/irecovery/releases/download/latest/irecovery_linux-x86_64.zip
unzip irecovery_linux-aarch64.zip
mv irecovery linux/aarch64/irecovery2
unzip irecovery_linux-x86_64.zip
mv irecovery linux/x86_64/irecovery2
rm -rf *.zip

curl -LO https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-arm64
curl -LO https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-amd64
mv jq-linux-arm64 linux/aarch64/jq
mv jq-linux-amd64 linux/x86_64/jq

curl -LO https://github.com/LukeZGD/KPlooshFinder/releases/download/latest/KPlooshFinder_linux-aarch64.zip
curl -LO https://github.com/LukeZGD/KPlooshFinder/releases/download/latest/KPlooshFinder_linux-x86_64.zip
unzip KPlooshFinder_linux-aarch64.zip
mv KPlooshFinder linux/aarch64/
unzip KPlooshFinder_linux-x86_64.zip
mv KPlooshFinder linux/x86_64/
rm -rf *.zip

curl -LO https://github.com/LukeZGD/xcbuild/releases/download/latest/build-aarch64.zip
curl -LO https://github.com/LukeZGD/xcbuild/releases/download/latest/build-x86_64.zip
unzip build-aarch64.zip
mv build/PlistBuddy linux/aarch64/
rm -rf build
unzip build-x86_64.zip
mv build/PlistBuddy linux/x86_64/
rm -rf build *.zip

curl -LO https://github.com/LukeZGD/powdersn0w_pub/releases/download/latest/powdersn0w_linux-aarch64.zip
curl -LO https://github.com/LukeZGD/powdersn0w_pub/releases/download/latest/powdersn0w_linux-x86_64.zip
unzip powdersn0w_linux-aarch64.zip
mv bin/powdersn0w bin/validate linux/aarch64/
unzip powdersn0w_linux-x86_64.zip
mv bin/powdersn0w bin/validate linux/x86_64/
rm -rf bin *.zip

curl -LO https://github.com/LukeZGD/primepwn/releases/download/latest/primepwn_linux-aarch64.zip
curl -LO https://github.com/LukeZGD/primepwn/releases/download/latest/primepwn_linux-x86_64.zip
unzip primepwn_linux-aarch64.zip
mv primepwn linux/aarch64/
unzip primepwn_linux-x86_64.zip
mv primepwn linux/x86_64/
rm -rf *.zip

curl -LO https://codeberg.org/binary-manu/static-cross-openssh/releases/download/weekly/ssh-binaries-for-aarch64.tar
curl -LO https://codeberg.org/binary-manu/static-cross-openssh/releases/download/weekly/ssh-binaries-for-x86-64.tar
tar -xvf ssh-binaries-for-aarch64.tar
tar -xvf openssh*
mv opt/openssh/bin/ssh opt/openssh/bin/scp linux/aarch64/
rm -rf config openssh* opt
tar -xvf ssh-binaries-for-x86-64.tar
tar -xvf openssh*
mv opt/openssh/bin/ssh opt/openssh/bin/scp linux/x86_64/
rm -rf config openssh* opt *.tar

curl -LO https://github.com/LukeZGD/sshpass/releases/download/latest/sshpass_linux-aarch64.zip
curl -LO https://github.com/LukeZGD/sshpass/releases/download/latest/sshpass_linux-x86_64.zip
unzip sshpass_linux-aarch64.zip
mv sshpass linux/aarch64/
unzip sshpass_linux-x86_64.zip
mv sshpass linux/x86_64/
rm -rf *.zip

curl -LO https://github.com/1Conan/tsschecker/releases/download/413/tsschecker_linux_aarch64
curl -LO https://github.com/1Conan/tsschecker/releases/download/413/tsschecker_linux_x86_64
mv tsschecker_linux_aarch64 linux/aarch64/tsschecker
mv tsschecker_linux_x86_64 linux/x86_64/tsschecker

curl -LO https://gist.github.com/LukeZGD/244d7dc3f07ec98a4505e4084c5dbf6b/raw/6e956a5a16143bc35f3e73f1f6be94b8966ca3f5/main.c
aarch64-linux-gnu-gcc main.c -o ipx_restored_patcher
mv ipx_restored_patcher linux/aarch64/
gcc main.c -o ipx_restored_patcher
mv ipx_restored_patcher linux/x86_64/

curl -LO https://gist.github.com/LukeZGD/8c719b613ca28d6883552437bdd500de/raw/e8f8ffa505265af2fac6a555670cacd24680ca8e/kerneldiff.c
aarch64-linux-gnu-gcc kerneldiff.c -o kerneldiff
mv kerneldiff linux/aarch64/
gcc kerneldiff.c -o kerneldiff
mv kerneldiff linux/x86_64/

chmod +x linux/aarch64/* linux/x86_64/*
