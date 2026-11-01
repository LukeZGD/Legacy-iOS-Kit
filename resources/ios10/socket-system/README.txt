Socket (Kit), development build 10

Derived from staturnzz/socket 1.3, commit 65e06a7ac35304b1f31cc6e279fe1abecac356f4.
Socket-LICENSE and source.json preserve attribution and upstream source hashes.
upstream/ is an unchanged reference snapshot. Only its exploit memory/offset
support is compiled, alongside the adapted SocketCore.m and local app controls.
The builder removes the unsupported ARM_14 condition in a build-local copy;
the intended devices are A6/A6X. Other upstream kernel patching and UI settings
are not compiled into this build.

No provision/profile/receipt or IPA-container check was found in the inspected
Socket source. Resources are resolved relative to the executable. This app is
restored under /Applications/LIKTools.app with root ownership and mode 0755.
The executable is ad-hoc signed; the temporary boot's code-signing patches are
still required to launch it before Procyon is installed.

SocketCore.m retains Socket's root credential routine. It requires the matching
device/build and a confirmed jump-start for first installation, then unpacks the
bundled runtime. The app manages installation itself and does not use the old
Unix-socket helper or the signed launchd startup cache. Run checks, SSH controls
and log export remain separate. Keep the app foregrounded during installation.

Build with socket-system/build.py --sdk <iPhoneOS10.3.sdk> --build-dir <directory>.
End users on macOS/Linux use the precompiled socket-system.tar.
