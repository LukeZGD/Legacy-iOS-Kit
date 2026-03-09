#!/bin/bash
set -x
mv /mnt1/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist /mnt1/System/Library/LaunchDaemons/
rm -rf /mnt1/Library/LaunchDaemons
mv /mnt1/System/Library/LaunchDaemons /mnt1/Library/LaunchDaemons
mv /mnt1/System/Library/NanoLaunchDaemons /mnt1/Library/NanoLaunchDaemons
mkdir -p /mnt1/System/Library/LaunchDaemons
mv /mnt1/Library/LaunchDaemons/bootps.plist /mnt1/System/Library/LaunchDaemons/
mv /mnt1/Library/LaunchDaemons/com.apple.CrashHousekeeping.plist /mnt1/System/Library/LaunchDaemons/
mv /mnt1/Library/LaunchDaemons/com.apple.MobileFileIntegrity.plist /mnt1/System/Library/LaunchDaemons/
mv /mnt1/Library/LaunchDaemons/com.apple.mobile.softwareupdated.plist /mnt1/System/Library/LaunchDaemons/com.apple.mobile.softwareupdated.plist_
mv /mnt1/Library/LaunchDaemons/com.apple.softwareupdateservicesd.plist /mnt1/System/Library/LaunchDaemons/com.apple.softwareupdateservicesd.plist_
mv /mnt1/Library/LaunchDaemons/com.apple.jetsamproperties.*.plist /mnt1/System/Library/LaunchDaemons/
if [[ $1 == "7"* ]]; then
    mv /mnt1/Library/LaunchDaemons/com.apple.sandboxd.plist /mnt1/System/Library/LaunchDaemons/
    mv /mnt1/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist /mnt1/System/Library/LaunchDaemons/
    mv /mnt1/usr/libexec/CrashHousekeeping /mnt1/usr/libexec/CrashHousekeeping.backup
    ln -sf /aquila /mnt1/usr/libexec/CrashHousekeeping
else
    mv /mnt1/Library/LaunchDaemons/com.apple.mDNSResponder.plist /mnt1/System/Library/LaunchDaemons/com.apple.mDNSResponder.plist_
    mv /mnt1/usr/libexec/CrashHousekeeping /mnt1/usr/libexec/CrashHousekeeping_o
fi
