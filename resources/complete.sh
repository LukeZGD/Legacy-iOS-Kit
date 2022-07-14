#!/bin/bash
# Download all external files/tools used by iOS-OTA-Downgrader

cd "$(dirname $0)"/..
curl -L https://github.com/LukeZGD/ipwndfu/archive/6e67c9e28a5f7f63f179dea670f7f858712350a0.zip -o ipwndfu.zip
curl -L https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/archive/refs/heads/master.zip -o keys.zip
curl -LO https://github.com/futurerestore/futurerestore/releases/download/194/futurerestore-v194-macOS.tar.xz
curl -LO https://github.com/futurerestore/futurerestore/releases/download/194/futurerestore-v194-ubuntu_20.04.2.tar.xz
mkdir tmp
cd tmp
7z x ../futurerestore-v194-macOS.tar.xz
tar -xf futurerestore*.tar
chmod +x futurerestore-v194
mv futurerestore-v194 ../resources/tools/futurerestore194_macos
rm -f ./*
7z x ../futurerestore-v194-ubuntu_20.04.2.tar.xz
tar -xf futurerestore*.tar
chmod +x futurerestore-v194
mv futurerestore-v194 ../resources/tools/futurerestore194_linux
cd ../resources/jailbreak
curl -LO https://github.com/LukeZGD/daibutsuCFW/raw/main/build/src/bin.tar
curl -LO https://github.com/LukeZGD/daibutsuCFW/raw/main/build/src/daibutsu/cydia.tar
curl -LO https://github.com/LukeZGD/daibutsuCFW/raw/main/build/src/daibutsu/untether.tar
curl -LO https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/jailbreak/Cydia5.tar
curl -LO https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/jailbreak/Cydia6.tar
curl -LO https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/jailbreak/Cydia7.tar
curl -LO https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/jailbreak/Cydia8.tar
curl -LO https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/jailbreak/sshdeb.tar
cd ..
unzip ../keys.zip -d .
unzip ../ipwndfu.zip -d .
cp -r iOS-OTA-Downgrader-Keys-master/* firmware
mv ipwndfu* ipwndfu
cd ..
rm -rf resources/iOS-OTA-Downgrader-Keys-master/ tmp/ futurerestore*.xz ipwndfu.zip keys.zip
