#!/usr/lik/bash
# Runs as an explicit launchd job, so closing the app does not kill
# the installer. An interrupted package operation is never blindly repeated.
set -eE -o pipefail
. /usr/local/share/lik-ios10/common.sh
read_identity
assert_jumpstart
init_journal
MODE=${1:-}
POSTINST=/var/lib/dpkg/info/com.staturnz.procyon.postinst
REPLACED=0

finish() {
    local result=$?
    trap - EXIT
    if [[ "$REPLACED" == 1 ]]; then
        "$R/cp" "$J/procyon.postinst.original" "$POSTINST" || result=1
        "$R/chmod" 755 "$POSTINST" || result=1
        "$R/cmp" "$J/procyon.postinst.original" "$POSTINST" || result=1
    fi
    if [[ "$result" != 0 ]]; then
        printf '%s\n' "$result" > "$J/last-exit-code"
        write_phase "$MODE-failed"
        printf 'Installation stopped; preserve this session and its logs. Do not run Socket.\n' >&2
    fi
    "$R/rm" -rf "$J/lock"
    "$R/sync"
    exit "$result"
}

case "$MODE:$(phase)" in
    bootstrap:new|untether:settings-ready) ;;
    *) fail "Cannot start $MODE from phase $(phase); inspect the saved state before recovery" ;;
esac
"$R/mkdir" "$J/lock" || fail 'Installer already running or interrupted; inspect the saved state'
trap finish EXIT
trap 'exit 130' INT TERM HUP
"$R/sysctl" -n kern.boottime > "$J/installer-boot"
verify_stage
/sbin/mount -uw /
[[ -w / ]] || fail 'System filesystem is not writable'

if [[ "$MODE" == bootstrap ]]; then
    assert_fresh
    write_phase bootstrap-running
    /Applications/LIKTools.app/LIKTools --socket-bootstrap
    grep -q '^Name: iOS Firmware$' /var/lib/dpkg/status || fail 'Firmware package registration failed'
    [[ -x /Applications/Zebra.app/Zebra ]] || fail 'Zebra installation failed'
    # The local worker edits the SpringBoard preference dictionary atomically in
    # the next phase. Do not replace it with a canned plist.
    write_phase needs-settings
else
    [[ ! -e /var/root/procyon && ! -L /var/root/procyon ]] || fail 'Procyon is already present'
    for required in /etc/racoon/racoon.conf /usr/libexec/backboardd \
        /usr/libexec/wifiFirmwareLoaderLegacy /var/db/com.apple.xpc.launchd/disabled.plist; do
        [[ -s "$required" && ! -L "$required" ]] || fail "Required stock backup input missing: $required"
    done
    capture before
    write_phase untether-running
    /usr/bin/dpkg --force-all --unpack "$D/procyon.deb"
    "$R/cmp" "$D/procyon-postinst" "$POSTINST" || fail 'Unexpected Procyon package script'
    "$R/cp" "$POSTINST" "$J/procyon.postinst.original"
    # Socket's unchanged postinst always exits zero, even when Procyon fails.
    # Use a temporary wrapper to record/propagate the binary's real exit status;
    # restore the exact upstream script on either success or failure.
    REPLACED=1
    "$R/cat" > "$POSTINST" <<'POSTINST_EOF'
#!/bin/bash
. /usr/local/share/lik-ios10/common.sh
read_identity
assert_jumpstart
[[ "$(phase)" == untether-running ]] || fail 'Unexpected Procyon invocation'
/usr/bin/procyon install
result=$?
printf '%s\n' "$result" > "$J/procyon-exit-code"
"$R/sync"
exit "$result"
POSTINST_EOF
    "$R/chmod" 755 "$POSTINST"
    if /Applications/LIKTools.app/LIKTools --socket-configure-untether; then
        [[ -f "$J/procyon-exit-code" && "$("$R/cat" "$J/procyon-exit-code")" == 0 ]] ||
            fail 'Procyon did not report successful installation'
    else
        capture failure || true
        fail 'Procyon configuration failed; see its actual result and saved capture'
    fi
    verify_untether
    "$R/cp" "$J/procyon.postinst.original" "$POSTINST"
    "$R/chmod" 755 "$POSTINST"
    "$R/cmp" "$J/procyon.postinst.original" "$POSTINST"
    REPLACED=0
    capture after
    : > /var/cache/.socket_1_2
    write_phase untether-installed
fi
