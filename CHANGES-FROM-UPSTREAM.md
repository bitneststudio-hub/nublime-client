# Changes from upstream (hiddify-app v4.1.2)

BitNest Studio's fork of hiddify-app (commit 54bc7eeb, 2026-03-05). Summary of the
material changes, newest first.

## Architecture

- Replaced the sing-box core with Xray-core via the libXray gomobile binding
  (`app/android/app/libs/libXray.aar`); added the `hev-socks5-tunnel` data plane.
- New Android VPN service: `com.nublime.vpn.XrayVpnService`, `XrayInvokeResult`,
  and `hev.htproxy.TProxyService` (replacing upstream's `com.hiddify.hiddify`
  service layer).
- New core supervisor and config conversion layer: `app/lib/nublimecore/`.

## Product

- Activation-code and subscription flow (`features/purchase`, `features/subscription`,
  `features/referral`, `features/devices`, `features/account`).
- Application rebrand: package id `com.nublime.vpn`, new visual identity, new strings.
- Telemetry disabled by default (compile-time switch `kEnableTelemetry`).

## Removed

- Upstream app-update pipeline pointing at Hiddify release feeds.
- Upstream free-profile sources.
- Upstream analytics and Sentry wiring (kept as an opt-in, off by default).

## Legal

- LICENSE replaced with the GNU GPL v3 text. Attribution and the additional terms
  that apply to the derived parts are stated in `SOURCE.md`.
