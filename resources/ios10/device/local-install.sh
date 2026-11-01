#!/usr/lik/bash
# Local app/worker actions. No host connection is needed.
set -eE -o pipefail
. /usr/local/share/lik-ios10/common.sh
read_identity
assert_jumpstart
init_journal
case "${1:-}" in
    settings)
        [[ "$(phase)" == needs-settings ]] || fail 'Package manager settings are not pending'
        /usr/bin/killall -9 cfprefsd || true
        "$R/chmod" 777 /private /private/var /private/var/mobile /private/var/mobile/Library /private/var/mobile/Library/Preferences
        sources='/var/mobile/Library/Application Support/xyz.willy.Zebra'
        "$R/mkdir" -p "$sources"
        "$R/chmod" 755 "$sources"
        "$R/chown" 501:501 "$sources"
        "$R/cat" > "$sources/sources.list" <<'SOURCES'
deb http://apt.saurik.com/ ios/1349.70 main
deb http://apt.thebigboss.org/repofiles/cydia/ stable main
deb http://modmyi.saurik.com/ stable main
deb https://repo.chariz.com/ ./
deb https://repo.packix.com/ ./
deb https://havoc.app/ ./
deb https://getzbra.com/repo ./
deb https://lukezgd.github.io/repo ./
SOURCES
        "$R/chmod" 644 "$sources/sources.list"
        /bin/su mobile -c /usr/bin/uicache || /usr/bin/uicache
        : > /.cydia_no_stash
        : > /.installed_socket
        write_phase settings-ready
        ;;
    verify)
        [[ "$(phase)" == untether-installed ]] || fail 'Untether installation is incomplete'
        verify_untether
        "$R/cmp" "$D/procyon-postinst" /var/lib/dpkg/info/com.staturnz.procyon.postinst || fail 'Procyon postinst was not restored'
        [[ "$("$R/cat" "$J/procyon-exit-code")" == 0 ]] || fail 'Procyon did not report successful installation'
        for path in etc/racoon/racoon.conf usr/libexec/backboardd usr/libexec/wifiFirmwareLoaderLegacy var/db/com.apple.xpc.launchd/disabled.plist; do
            "$R/tar" -xOf "$J/before.tar" "$path" > "$J/verify-original"
            "$R/cmp" "$J/verify-original" "/var/root/procyon/backup/${path##*/}" || fail "Stock backup mismatch: $path"
        done
        "$R/rm" -f "$J/verify-original"
        [[ -x /Applications/Zebra.app/Zebra && -s /var/lib/dpkg/status && -f /.installed_socket ]] || fail 'Jailbreak assets are incomplete'
        printf 'Persistent installation and all four original backups verified.\n'
        ;;
    *) fail 'Unknown local installation operation';;
esac
