<div align="center">

# 🔥 HotShare

**Zero-Cloud, High-Speed P2P Hotspot File Transfer between Android & Windows**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Windows-FF4500?style=for-the-badge)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)](LICENSE)

*Direct local Wi-Fi / Hotspot transfers at hardware line-rate speed — no cables, no internet, no cloud, no tracking.*

---

### 📥 [Download Latest Release](https://github.com/hotshare/hotshare/releases/latest)

| Platform | Download | Format | Compatibility |
| :--- | :--- | :--- | :--- |
| **Windows** | [**HotShare-Setup-x64.exe**](https://github.com/hotshare/hotshare/releases/latest) | Installer (.exe) | Windows 10 / 11 (64-bit) |
| **Android** | [**app-release.apk**](https://github.com/hotshare/hotshare/releases/latest) | Universal APK | Android 10.0+ (API 29+) |

---

</div>

## 🌟 Highlights

* ⚡ **Blazing Fast (20–40+ MB/s):** Pure Dart streaming byte-pipeline with credit-window flow control over 5 GHz mobile hotspot.
* 🛡️ **Zero Cloud & True Privacy:** Sockets never touch external servers or the internet. All data transfers remain strictly within your local radio link.
* 🔐 **Cryptographic Device Identity:** Ed25519 public-key authentication with 6-digit PIN and SAS (Short Authentication String) verification.
* 🌌 **Ember Liquid Glass Design:** Deep obsidian dark canvas (`#0B0808`), live frosted glassmorphism (sigma-18 backdrop blur), and glowing animated status rings.
* 📡 **Interactive Topology Radar:** Visual living bridge and flowing neon photon progress pulses indicating real-time link health and throughput.
* 💻 **Windows Desktop Power:**
  * System tray minimization & background transfer support.
  * Windows Explorer right-click **"Send to"** integration (`hotshare.exe --send`).
  * Direct drag-and-drop file target on the desktop window.
  * Self-contained Visual C++ runtime bundling (runs smoothly on fresh Windows installs).
* 📱 **Android Native Integration:**
  * Persistent foreground service with progress notification.
  * Native Android Share Sheet target (`ACTION_SEND` & `ACTION_SEND_MULTIPLE`).
  * Automatic MediaStore indexing so received media instantly appears in Gallery & Downloads.

---

## 🚀 Quick Start Guide

### 1. Connect
1. Turn on **Mobile Hotspot** on your Android phone.
2. Connect your Windows PC to the phone's Wi-Fi network.
3. Open **HotShare** on both devices.
4. HotShare automatically resolves the network gateway and connects within seconds.

### 2. Pair (First Time Only)
1. Tap **"Show My PIN"** on one device (generates a secure 6-digit code).
2. Tap **"Enter PIN"** on the other device and type the code.
3. Both devices securely exchange and save Ed25519 public keys. Future transfers between paired devices are authenticated automatically.

### 3. Transfer
* **From Windows:** Click **"Choose or drop files to send"**, or drag any file directly into the app window. You can also right-click any file in Windows Explorer $\rightarrow$ **Send to** $\rightarrow$ **HotShare**.
* **From Android:** Tap **"Send files"**, or use your phone's native **Share** button from any file manager, gallery, or app.

---

## 🏗️ Architecture & Technology Stack

HotShare separates pure Dart network orchestration from presentation:

```
hotshare/
├── lib/
│   ├── app/                # Platform shells (Desktop / Mobile navigation & titlebars)
│   ├── core/
│   │   ├── engine/         # Pure Dart HotShareEngine (protocol, sockets, chunk streaming)
│   │   ├── security/       # Cryptographic identity (Ed25519 keys, SHA-256, SAS)
│   │   ├── net/            # Network gateway discovery (route table metric parsing)
│   │   ├── storage/        # Cross-platform file resolution & MediaStore scanner
│   │   └── platform/       # Windows Tray & Android Foreground Service glue
│   ├── data/
│   │   └── db/             # Drift SQLite database (transfer history, trusted devices)
│   ├── state/              # Riverpod notifiers (engine events, connection, transfers)
│   └── ui/
│       ├── design_system/  # Ember Liquid Glass tokens (GlassSurface, GlassButton, HsColors)
│       └── features/       # Radar stage, devices list, history records, settings, pairing
├── android/                # Android native project (Kotlin Share Target & Foreground Service)
└── windows/                # Windows native runner & Inno Setup installer scripts
```

* **Framework:** [Flutter](https://flutter.dev) (Dart 3.x)
* **State Management:** [Flutter Riverpod](https://pub.dev/packages/flutter_riverpod)
* **Persistence & Database:** [Drift](https://drift.simonbinder.eu/) (SQLite)
* **Networking:** Pure Dart WebSocket & streaming byte pipeline
* **Security & Crypto:** Ed25519 digital signatures (`cryptography`), SHA-256 integrity verification (`crypto`)
* **Windows Packaging:** [Inno Setup 6](https://jrsoftware.org/isinfo.php)

---

## 🛠️ Building from Source

### Prerequisites
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.24+ recommended)
* [Android SDK](https://developer.android.com/studio) (for Android builds)
* [Visual Studio](https://visualstudio.microsoft.com/) with "Desktop development with C++" (for Windows builds)
* [Inno Setup 6](https://jrsoftware.org/isdl.php) (optional, for compiling the Windows installer)

### 1. Clone the Repository
```bash
git clone https://github.com/hotshare/hotshare.git
cd hotshare
flutter pub get
```

### 2. Build for Android
To build a single universal release APK:
```bash
flutter build apk --release
```
*Output:* `build/app/outputs/flutter-apk/app-release.apk`

### 3. Build for Windows
```bash
flutter build windows --release
```
*Output:* `build\windows\x64\runner\Release\`

### 4. Build Windows Installer (.exe)
```powershell
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" windows\installer\hotshare_setup.iss
```
*Output:* `build\installer\HotShare-Setup-x64.exe`

---

## 🔒 Security & Privacy

* **No Telemetry / No Tracking:** Zero tracking SDKs or remote analytics.
* **Ephemeral Sockets:** Data is transmitted exclusively through direct local sockets.
* **Integrity Checked:** Every file transfer is verified via cryptographic SHA-256 checksums before finalizing on disk.
* **Explicit Trust:** Unpaired devices cannot push files without entering a 6-digit confirmation PIN.

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
