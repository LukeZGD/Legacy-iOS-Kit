#!/bin/bash
# Download all external files/tools used by iOS-OTA-Downgrader

cd "$(dirname $0)"/..
curl -L https://github.com/LukeZGD/ipwndfu/archive/6e67c9e28a5f7f63f179dea670f7f858712350a0.zip -o ipwndfu.zip
curl -L https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/archive/refs/heads/master.zip -o keys.zip
cd resources/jailbreak
curl -LO https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/jailbreak/Cydia5.tar
curl -LO https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/jailbreak/Cydia6.tar
curl -LO https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/jailbreak/Cydia7.tar
curl -LO https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/jailbreak/Cydia8.tar
cd ..
unzip ../keys.zip -d .
unzip ../ipwndfu.zip -d .
cp -r iOS-OTA-Downgrader-Keys-master/* firmware
mv ipwndfu* ipwndfu
cd ..
rm -rf resources/iOS-OTA-Downgrader-Keys-master/ ipwndfu.zip keys.zip
