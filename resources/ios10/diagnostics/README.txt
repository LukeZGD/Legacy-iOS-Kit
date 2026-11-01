iOS 10 Tools — diagnostic build

This source belongs to the Custom Legacy iOS Kit, under its repository license.
It produces a native ARMv7 app and launchd helper for iOS 10. Neither component
runs an exploit or installs Procyon. They observe the temporary boot and offer
explicit restart/repair actions for this kit's private SSH transport.

To rebuild on macOS with Apple command-line tools and an iPhoneOS 10.3 SDK:
  python3 resources/ios10/diagnostics/build.py --sdk /path/iPhoneOS10.3.sdk --build-dir /path/build

The packaged diagnostics.tar and diagnostics-build.json are checksum-pinned in
assets/manifest.json. Users on macOS/Linux need no SDK or compiler. The build
records source hashes, SDK archive provenance and all packaged file hashes.
The SDK itself is not distributed. Apple's ld-classic is used for ARMv7; modern
ld versions can omit 32-bit iOS support. Build-local TBD adjustments address the
merged SDK's simulator metadata and missing standard libSystem declarations.
The original SDK is preserved. Actual app execution on iOS still needs testing.

The root helper runs from /usr/local/share/lik-ios10 and uses stock libraries.
The app runs normally from /Applications/LIKTools.app and requests fixed actions
over /var/run/lik-ios10-diagnostics.sock (root:mobile 0660). The helper checks
peer UID and accepts only status, restart-ssh and repair-ssh, with bounded input.
It does not accept arbitrary commands, paths or install requests. Native tests
exercise the same client and its malformed/oversized-response handling.

Repair uses per-session backup hashes and root-owned fixed paths; it may remount
the system writable. It never restores a generic public SSH credential. The
private host authentication key is not included in the IPSW. Reports contain
file metadata, not private-key bytes. All repair/restart actions require a user
tap and confirmation, and the app records their actual result rather than
assuming launchctl success means SSH is accepting connections.

The helper enables non-default system app visibility and requests LaunchServices
registration. Registration and privileges are runtime observations, not proof
that the full jailbreak or untether has been installed. Complete Setup normally.
Hardware validation of icon visibility, app launch and repair remains pending.
