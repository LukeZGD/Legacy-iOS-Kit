#!/bin/bash

# 8.4.1 iBSS IV and Keys
IV_k93=781b9672a86ba1b41f8b7fa0af714c94 #iPad2,1
Key_k93=bbd7bf676dbcc6ba93c76d496b7af39ae7772eaaad2ec9fb71dc1fd004827784
IV_k94=883c92ed915e4d2481570a062583495b #iPad2,2
Key_k94=ccfadf3732904885d38f963cce035d7e03b387b67212d526503c85773b58e52f
IV_k95=460116385cca6d5596221c58ae122669 #iPad2,3
Key_k95=7852f1fd93d9d49ebea44021081e8f1dffa336d0d3e9517374f8be451dd92eb7
IV_k93a=976aa656929ac699fff36715de96876d #iPad2,4
Key_k93a=5fe5c47b5620c2b40b1ca2bd1764a92d568901a24e1caf8faf0cf0f84ae11b4e
IV_p105=b21abc8689b0dea8f6e613f9f970e241 #iPad2,5
Key_p105=b9ed63e4a31f5d9d4d7dddc527e65fd31d1ea48c70204e6b44551c1e6dfc52b5
IV_p106=56231fd62c6296ed0c8c411bcef602e0 #iPad2,6
Key_p106=cdb2142489e5e936fa8f3540bd036f62ed0f27ddb6fec96b9fbfec5a65bc5f17
IV_p107=fa39c596b6569e572d90f0820e4e4357 #iPad2,7
Key_p107=34b359fcc729a0f0d2853e786a78b245ed36a9212c8296aaab95dc0401cf07de
IV_j1=c3ea87ed43788dfc3e268abdf1af27dd #iPad3,1
Key_j1=cd3dd7eee07b9ce8b180d1526632cf86dc7fef7d52352d06af354598ab9cf2ef
IV_j2=32fcd912cb9a472ef2a6db72596ae01c #iPad3,2
Key_j2=076720d5a07e8011bdda6f6eafaf4845b40a441615cd1d7c1a9cca438ce7db17
IV_j2a=e6b041970cd611c8a1561a4c210bc476 #iPad3,3
Key_j2a=aec6a888d45bd26106ac620d7d4ec0c160ab80276deedc1b50ce8f5d99dcc9af
IV_p101=a5892a58c90b6d3fb0e0b20db95070d7 #iPad3,4
Key_p101=75612774968009e3f85545ac0088d0d0bb9cb4e2c2970e8f88489be0b9dfe103
IV_p102=fba6d9aaec7237891c80390e6ffa88bf #iPad3,5
Key_p102=92909dca9bfdb9193131f9ad9b628b1a4971b1cbab52c0ddd114a6253fad96c0
IV_p103=1d99e780d96c32a25ca7e4b1c7fe14c0 #iPad3,6
Key_p103=4e2c14927693d61e1da375e340061521c9376007163f6ab55afbe1a03b901fd3
IV_n94=147cdef921ed14a5c10631c5e6e02d1e #iPhone4,1
Key_n94=6ea1eb62a9f403ee212c1f6b3039df093963b46739c6093407190fe3d750c69c
IV_n41=bd0c8b039a819604a30f0d39adf88572 #iPhone5,1
Key_n41=baf05fe0282f78c18c2e3842be4f9021919d586b55594281f5b5abd0f6e61495
IV_n42=fdad2b7a35384fa2ffc7221213ca1082 #iPhone5,2
Key_n42=74cd68729b800a20b1f8e8a3cb5517024a09f074eaa05b099db530fb5783275e
IV_n48=dbecd5f265e031835584e6bfbdb4c47f #iPhone5,3
Key_n48=248f86d983626b75d26718fa52732eca64466ab73df048f278e034a272041f7e
IV_n49=039241f2b0212bb7c7b62ab4deec263f #iPhone5,4
Key_n49=d0b49d366469ae2b1580d7d31b1bcf783d835e4fac13cfe9f9a160fa95010ac4
IV_n78=e0175b03bc29817adc312638884e0898 #iPod5,1
Key_n78=0a0e0aedc8171669c9af6a229930a395959df55dcd8a3ee1fe0f4c009007df3c

# 6.1.3 iBSS IV and Keys
IV_k93_613=b69f753dccd09c9b98d345ec73bbf044 #iPad2,1
Key_k93_613=6e4cce9ea6f2ec346cba0b279beab1b43e44a0680f1fde789a00f66a1e68ffab
IV_k94_613=bc3c9f168d7fb86aa219b7ad8039584b #iPad2,2
Key_k94_613=b1bd1dc5e6076054392be054d50711ae70e8fcf31a47899fb90ab0ff3111b687
IV_k95_613=56f964ee19bfd31f06e43e9d8fe93902 #iPad2,3
Key_k95_613=0bb841b8f1922ae73d85ed9ed0d7a3583a10af909787857c15af2691b39bba30
IV_n94_613=d3fe01e99bd0967e80dccfc0739f93d5 #iPhone4,1
Key_n94_613=35343d5139e0313c81ee59dbae292da26e739ed75b3da5db9da7d4d26046498c

devices=(iPhone4,1 iPhone5,1 iPhone5,2
iPad2,1 iPad2,2 iPad2,3 iPad2,4 iPad2,5 iPad2,6 iPad2,7
iPad3,1 iPad3,2 iPad3,3 iPad3,4 iPad3,5 iPad3,6 iPod5,1
)
devices613=(iPhone4,1 iPad2,1 iPad2,2 iPad2,3)

if [[ $OSTYPE == "linux-gnu" ]]; then
    platform='linux'
elif [[ $OSTYPE == "darwin"* ]]; then
    platform='macos'
fi

function HWModel {
    if [ $ProductType == iPad2,1 ]; then
        HWModelLower=k93
    elif [ $ProductType == iPad2,2 ]; then
        HWModelLower=k94
    elif [ $ProductType == iPad2,3 ]; then
        HWModelLower=k95
    elif [ $ProductType == iPad2,4 ]; then
        HWModelLower=k93a
    elif [ $ProductType == iPad2,5 ]; then
        HWModelLower=p105
    elif [ $ProductType == iPad2,6 ]; then
        HWModelLower=p106
    elif [ $ProductType == iPad2,7 ]; then
        HWModelLower=p107
    elif [ $ProductType == iPad3,1 ]; then
        HWModelLower=j1
    elif [ $ProductType == iPad3,2 ]; then
        HWModelLower=j2
    elif [ $ProductType == iPad3,3 ]; then
        HWModelLower=j2a
    elif [ $ProductType == iPad3,4 ]; then
        HWModelLower=p101
    elif [ $ProductType == iPad3,5 ]; then
        HWModelLower=p102
    elif [ $ProductType == iPad3,6 ]; then
        HWModelLower=p103
    elif [ $ProductType == iPhone4,1 ]; then
        HWModelLower=n94
    elif [ $ProductType == iPhone5,1 ]; then
        HWModelLower=n41
    elif [ $ProductType == iPhone5,2 ]; then
        HWModelLower=n42
    elif [ $ProductType == iPhone5,3 ]; then
        HWModelLower=n48
    elif [ $ProductType == iPhone5,4 ]; then
        HWModelLower=n49
    elif [ $ProductType == iPod5,1 ]; then
        HWModelLower=n78
    fi
}

echo "32bit-OTA-Downgrader BuildManifest and Firmware Keys Saver"
echo "- by LukeZGD"

for ProductType in "${devices[@]}"
do
    mkdir -p firmware/$ProductType/12H321
    #dllink=$(curl -I -Ls -o /dev/null -w %{url_effective} https://api.ipsw.me/v4/ota/download/${ProductType}/12H321?prerequisite=12H143)
    #tools/pzb_$platform -g AssetData/boot/BuildManifest.plist -o BuildManifest_${ProductType}_8.4.1.plist $dllink
    #curl -L https://firmware-keys.ipsw.me/firmware/$ProductType/12H321 -o firmware/$ProductType/12H321/index.html
    curl -L https://api.ipsw.me/v2.1/${ProductType}/12H321/sha1sum -o firmware/$ProductType/12H321/sha1sum
    curl -L https://api.ipsw.me/v2.1/${ProductType}/12H321/url -o firmware/$ProductType/12H321/url
    HWModel
    IV=IV_$HWModelLower
    Key=Key_$HWModelLower
    echo ${!Key} | tee firmware/$ProductType/12H321/key
    echo ${!IV} | tee firmware/$ProductType/12H321/iv
done

for ProductType in "${devices613[@]}"
do
    mkdir -p firmware/$ProductType/10B329
    #dllink=$(curl -I -Ls -o /dev/null -w %{url_effective} https://api.ipsw.me/v4/ota/download/${ProductType}/10B329?prerequisite=10B146)
    #tools/pzb_$platform -g AssetData/boot/BuildManifest.plist -o BuildManifest_${ProductType}_6.1.3.plist $dllink
    #curl -L https://firmware-keys.ipsw.me/firmware/$ProductType/10B329 -o firmware/$ProductType/10B329/index.html
    curl -L https://api.ipsw.me/v2.1/${ProductType}/10B329/sha1sum -o firmware/$ProductType/10B329/sha1sum
    curl -L https://api.ipsw.me/v2.1/${ProductType}/10B329/url -o firmware/$ProductType/10B329/url
    HWModel
    IV=IV_${HWModelLower}_613
    Key=Key_${HWModelLower}_613
    echo ${!Key} | tee firmware/$ProductType/10B329/key
    echo ${!IV} | tee firmware/$ProductType/10B329/iv
done

mkdir -p firmware/iPad2,2/13G36
curl -L https://api.ipsw.me/v2.1/iPad2,2/13G36/url -o firmware/iPad2,2/13G36/url

for ProductType in iPad2,3 iPad2,6 iPad2,7 iPad3,2 iPad3,3 iPhone4,1
do
    mkdir -p firmware/$ProductType/13G37
    curl -L https://api.ipsw.me/v2.1/${ProductType}/13G37/url -o firmware/$ProductType/13G37/url
done

for ProductType in iPhone5,1 iPhone5,2 iPad3,5 iPad3,6
do
    mkdir -p firmware/$ProductType/14G61
    curl -L https://api.ipsw.me/v2.1/${ProductType}/14G61/url -o firmware/$ProductType/14G61/url
done

mkdir manifests
mv *.plist manifests
