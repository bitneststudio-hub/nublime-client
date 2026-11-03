# Building this application

This repository contains the **client application source code** (Flutter/Dart + Android native layer)
for NuBLime VPN. It intentionally does **not** contain prebuilt third-party binaries; they are
obtained from their upstream releases as described below.

## 1. Prerequisites

- Flutter 3.38.5 (Dart 3.10.4) — the version in `app/pubspec.yaml` is enforced by the build scripts.
- Android SDK with NDK (version pinned by the Flutter toolchain), JDK 17.
- For the VPN core: Go 1.26.x and `gomobile` (only needed if you rebuild the core yourself).

## 2. Third-party components you must supply

| Component | How to obtain |
|---|---|
| `app/android/app/libs/libXray.aar` | Build from https://github.com/XTLS/libXray at tag `v26.6.27` using `gomobile bind`; or download the release artifact of the same tag. |
| `app/android/app/src/main/jniLibs/<abi>/libgojni.so` | Produced by the same `libXray` build (the AAR contains these; extract or copy them). |
| `app/android/app/src/main/assets/geoip.dat`, `geosite.dat` | Optional. Only needed if you use geo-based routing rules; obtain from https://github.com/Loyalsoldier/v2ray-rules-dat (or any compatible source). The app runs without them. |

License texts and upstream links for all bundled components are in `NOTICE`.

## 3. Build

```bash
cd app
flutter pub get
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

Signing is configured through `android/key.properties` (not included in this repository).
Create your own keystore and point `key.properties` at it.

## 4. Reproducing a release

Each published release is tagged in this repository (`v<version>`).
To reproduce, check out the tag, supply the third-party binaries listed above,
and run the build command in §3.
