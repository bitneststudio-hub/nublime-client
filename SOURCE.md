# Source code availability

This repository is the complete corresponding source code for the NuBLime VPN client,
published to satisfy the GNU GPL v3 (section 6) for every binary we distribute.

| Released version | Tag | Notes |
|---|---|---|
| 4.1.42 (Android, versionCode 42142) | `v4.1.42` | first public source publication |
| 4.1.16 – 4.1.42 | same as version | corresponding source archives: https://github.com/bitneststudio-hub/nublime-client/releases/tag/android-source-archives |
| 4.1.43 (current) | v4.1.43 | this repository, tag `v4.1.43`; archive: https://github.com/bitneststudio-hub/nublime-client/releases/tag/v4.1.43 |
| 4.1.0 – 4.1.15 | not distributed | development builds only; never offered to customers. First publicly distributed version is 4.1.16 (see archive release). |

Third-party binaries are not stored in this repository; see `BUILD.md`.

## Attribution

Parts of this program are derived from hiddify-app by the Hiddify team
(https://github.com/hiddify/hiddify-app), version v4.1.2 (commit 54bc7eeb).
Original license: https://github.com/hiddify/hiddify-app/blob/v4.1.2/LICENSE.md

Modified by BitNest Studio, March-November 2026. A summary of changes is in
CHANGES-FROM-UPSTREAM.md.

This program, as distributed by BitNest Studio, is licensed under the GNU General
Public License version 3 (see LICENSE). For the parts derived from hiddify-app, the
following additional terms under GPLv3 section 7 apply: attribution to Hiddify must be
preserved; modified versions must be marked as different from the original; the
Hiddify name and logos may not be used to name or promote derived works.

Third-party components and their licenses are listed in NOTICE.

## Source availability for third-party libraries

- `libXray` v26.6.27 / `Xray-core` v26.6.27: corresponding source archive:
  https://github.com/bitneststudio-hub/nublime-client/releases/tag/libxray-source-v26.6.27
  (vendored Go modules, build command, and `go version -m` of the shipped `.so` inside).
  `BUILD.md` explains how it maps to `app/android/app/libs/libXray.aar`.
- `hev-socks5-tunnel`: https://github.com/heiher/hev-socks5-tunnel
- Dart/Flutter packages: pinned versions in `app/pubspec.lock`; license texts are
  shipped inside each package from pub.dev.
