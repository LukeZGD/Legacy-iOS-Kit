#!/usr/bin/env bash
export MACOSX_DEPLOYMENT_TARGET=10.11

mkdir -p output

curl -L -o aria2c.arm64 https://github.com/agalwood/Motrix/raw/refs/heads/master/extra/darwin/arm64/engine/aria2c
curl -L -o aria2c.x86_64 https://github.com/agalwood/Motrix/raw/refs/heads/master/extra/darwin/x64/engine/aria2c
lipo -create -output output/aria2c aria2c.x86_64 aria2c.arm64

curl -LO https://gist.github.com/mineek/16c2607c928477dcd273e680e40a1c90/raw/13ab7a939551a46ae29ebaeb6cd4d706174ebfa6/main.c
cc -O main.c -o output/ipx_restored_patcher -arch x86_64 -arch arm64

git clone --filter=blob:none https://github.com/dora2ios/iPwnder32
cd iPwnder32
./BUILD --intel
cp iPwnder32 ../output/ipwnder32
cd ..

curl -L -o jq.arm64 https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-macos-arm64
curl -L -o jq.x86_64 https://github.com/jqlang/jq/releases/download/jq-1.6/jq-osx-amd64
lipo -create -output output/jq jq.x86_64 jq.arm64

curl -LO https://gist.github.com/LukeZGD/8c719b613ca28d6883552437bdd500de/raw/e8f8ffa505265af2fac6a555670cacd24680ca8e/kerneldiff.c
cc -O kerneldiff.c -o output/kerneldiff -arch x86_64 -arch arm64

curl -LO https://github.com/tihmstar/partialZipBrowser/releases/download/44/buildroot_macos-latest.zip
unzip buildroot_macos-latest.zip
mv buildroot_macos-latest/usr/local/bin/pzb pzb.arm64
curl -LO https://github.com/tihmstar/partialZipBrowser/releases/download/36/buildroot_macos-latest.zip
unzip buildroot_macos-latest.zip
mv buildroot_macos-latest/usr/local/bin/pzb pzb.x86_64
lipo -create -output output/pzb pzb.x86_64 pzb.arm64

curl -LO https://github.com/ncruces/zenity/releases/download/v0.10.14/zenity_macos.zip
unzip zenity_macos.zip
mv zenity output/
