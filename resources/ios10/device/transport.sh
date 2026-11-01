#!/usr/lik/bash
# This is sshd's forced command. Never eval SSH_ORIGINAL_COMMAND, source host
# input, or provide a general root shell. Each request is a literal operation.
set -eE -o pipefail
. /usr/local/share/lik-ios10/common.sh
read_identity
assert_identity

case "${SSH_ORIGINAL_COMMAND:-}" in
    info)
        printf 'session=%s\nproduct=%s\nboard=%s\nversion=%s\nbuild=%s\necid=%s\nuid=%s\nphase=%s\n' \
            "$SESSION" "$PRODUCT" "$BOARD" "$VERSION" "$BUILD" "$ECID" "$EUID" "$(phase)"
        printf 'boot='; "$R/sysctl" -n kern.boottime
        printf 'bootargs='; "$R/sysctl" -n kern.bootargs
        ;;
    start-bootstrap|start-untether)
        assert_jumpstart
        init_journal
        job=${SSH_ORIGINAL_COMMAND#start-}
        case "$job:$(phase)" in bootstrap:new|untether:settings-ready) ;;
            *) fail "Cannot start $job from phase $(phase)" ;; esac
        "$D/launchctl" load "$D/$job.plist"
        ;;
    get-settings)
        [[ "$(phase)" == needs-settings ]] || fail 'Not ready for SpringBoard settings'
        if [[ -f /var/mobile/Library/Preferences/com.apple.springboard.plist ]]; then
            "$R/cat" /var/mobile/Library/Preferences/com.apple.springboard.plist
        fi
        ;;
    put-settings)
        assert_jumpstart
        [[ "$(phase)" == needs-settings ]] || fail 'Not ready for SpringBoard settings'
        # Host sends a parsed/validated plist and verifies these bytes before
        # requesting apply-settings. No uploaded data is executed.
        "$R/dd" of="$J/springboard.plist.new" bs=1024 count=2049
        ;;
    get-staged-settings)
        [[ "$(phase)" == needs-settings ]] || fail 'Not ready for SpringBoard settings'
        "$R/cat" "$J/springboard.plist.new"
        ;;
    apply-settings)
        assert_jumpstart
        [[ "$(phase)" == needs-settings ]] || fail 'Not ready for SpringBoard settings'
        [[ -s "$J/springboard.plist.new" ]] || fail 'Settings upload missing'
        "$R/mkdir" -p /var/mobile/Library/Preferences
        "$R/cp" "$J/springboard.plist.new" /var/mobile/Library/Preferences/com.apple.springboard.plist.lik-new
        "$R/chown" 501:501 /var/mobile/Library/Preferences/com.apple.springboard.plist.lik-new
        "$R/chmod" 600 /var/mobile/Library/Preferences/com.apple.springboard.plist.lik-new
        "$R/mv" /var/mobile/Library/Preferences/com.apple.springboard.plist.lik-new \
            /var/mobile/Library/Preferences/com.apple.springboard.plist
        /usr/bin/killall -9 cfprefsd || true
        # Keep Socket's normal preference-directory permissions and sources.
        "$R/chmod" 777 /private /private/var /private/var/mobile \
            /private/var/mobile/Library /private/var/mobile/Library/Preferences
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
    bootstrap-log|untether-log)
        file="$J/${SSH_ORIGINAL_COMMAND%-log}.log"
        [[ ! -f "$file" ]] || "$R/cat" "$file"
        ;;
    before-capture|after-capture|failure-capture)
        file="$J/${SSH_ORIGINAL_COMMAND%-capture}.tar"
        [[ -f "$file" ]] || fail 'Capture is not available'
        "$R/cat" "$file"
        ;;
    arm-cold-boot)
        assert_jumpstart
        [[ "$(phase)" == untether-installed ]] || fail 'Untether installation is incomplete'
        verify_untether
        "$R/sysctl" -n kern.boottime > "$J/pre-cold-boot"
        "$R/sync"
        ;;
    reboot)
        assert_jumpstart
        [[ "$(phase)" == untether-installed && -s "$J/pre-cold-boot" ]] || fail 'Cold boot is not armed'
        "$R/sync"
        /sbin/reboot
        ;;
    cold-boot-proof)
        [[ "$(phase)" == untether-installed && -s "$J/pre-cold-boot" ]] || fail 'No pending cold boot'
        [[ "$($R/sysctl -n kern.boottime)" != "$("$R/cat" "$J/pre-cold-boot")" ]] || fail 'Still the previous boot'
        [[ " $($R/sysctl -n kern.bootargs) " != *' lik_ios10_jumpstart=1 '* ]] || fail 'Still using the temporary patched boot'
        printf 'session=%s\nuid=%s\nboot=' "$SESSION" "$EUID"
        "$R/sysctl" -n kern.boottime
        /bin/ps -A
        ;;
    *) fail 'Unknown installer operation' ;;
esac
