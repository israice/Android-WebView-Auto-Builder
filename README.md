<div align="center">

# 🚀 Android-WebView-Auto-Builder
### Turn any URL into an APK in seconds. Zero Setup.


[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-blue?style=for-the-badge&logo=linux)](https://github.com/)
[![Dependencies](https://img.shields.io/badge/Dependencies-None-success?style=for-the-badge)](https://github.com/)
[![License](https://img.shields.io/badge/License-MIT-orange?style=for-the-badge)](https://github.com/)
[![Build](https://img.shields.io/badge/Build-Automated-brightgreen?style=for-the-badge&logo=android)](https://github.com/)
<br>
[![GitHub Stars](https://img.shields.io/github/stars/israice/Android-WebView-Auto-Builder?style=for-the-badge&logo=github&color=gold)](https://github.com/)
[![GitHub Forks](https://img.shields.io/github/forks/israice/Android-WebView-Auto-Builder?style=for-the-badge&logo=github&color=blue)](https://github.com/)
[![Last Commit](https://img.shields.io/github/last-commit/israice/Android-WebView-Auto-Builder?style=for-the-badge&logo=git&color=red)](https://github.com/)
[![Repo Size](https://img.shields.io/github/repo-size/israice/Android-WebView-Auto-Builder?style=for-the-badge&logo=files&color=success)](https://github.com/)

<p align="center">
  <b>No Android Studio. No Java installation required. No headaches.</b><br>
  Just run the script, and get your APK.
</p>

</div>

<img src="CORE/screenshot1.png" alt="Описание" width="300">

<img src="CORE/screenshot2.png" alt="Описание" width="300">

<img src="CORE/screenshot3.png" alt="Описание" width="300">


## 🚀 Live Website

> **Try it instantly:**  
> https://apk.weforks.org/

## ⚡ Why this exists?
Building a simple WebView app shouldn't require installing **20GB** of Android Studio. 
This tool automates the entire toolchain:
1.  **Downloads** portable Java & Android SDK (sandboxed).
2.  **Generates** a minimal, optimized Android project.
3.  **Builds** the APK using Gradle.
4.  **Cleans up** everything, leaving your system spotless.

---

## 🚀 Quick Start

### 1. Configure
Edit `settings.yaml` to set your target URL and App Name:
```yaml
redirect_to_url: "https://your-website.com"
apk_name: "MyApp.apk"
```

### 2. Build
Run the magic script for your OS:

#### 🪟 Windows
```powershell
.\CORE\windows_build_apk.ps1
```

#### 🐧 Linux / 🍎 macOS
```bash
chmod +x CORE/linux_mac_build_apk.sh
./CORE/linux_mac_build_apk.sh
chmod +x CORE/linux_mac_build_apk.sh
./CORE/linux_mac_build_apk.sh
```

#### 🐳 Docker
```bash
docker compose up --build -d
```

### 3. Done!
Your APK will appear in the `FINISHED_HERE` folder:
`📂 ./FINISHED_HERE/MyApp.apk`

---

## 🛠️ Features
-   **📦 Zero Dependencies:** Uses portable versions of OpenJDK and Command Line Tools.
-   **🛡️ Sandboxed:** All build tools are kept in `android_build_env` and removed after building.
-   **⚡ Lightning Fast:** Uses `curl` and `tar` for maximum download/extraction speed.
-   **🔄 Smart Caching:** Downloads tools once. Subsequent builds are instant.
-   **🔒 Secure:** No admin rights required. No system environment variables changed.
-   **🌐 Web Dashboard:** Beautiful 3D interactive UI with real-time progress tracking.
-   **👥 Multi-User Concurrency:** Supports multiple simultaneous builds with isolated environments.
-   **💾 Session Persistence:** Refreshing the page doesn't lose your build progress.

---
<details>


<summary>DEV Roadmap</summary>

- [x] v0.0.10 readme.md updated
- [x] v0.0.9 added to server apk.weforks.org
- [x] v0.0.8 screenshots added to README.md
- [x] v0.0.7 Implement APK Signing & Keystor management
- [x] v0.0.6 Web UI with 3D background & SessionPersistence
- [x] v0.0.5 Multi-user concurrency suppor
- [x] v0.0.4 Added Docker support for isolate builds
- [x] v0.0.3 Added Linux & macOS support (Bash sript)
- [x] v0.0.2 Implemented "Jokes Progress Bar" & I polish
- [x] v0.0.1 Initial Windows PowerShell automation

### Github Update
```bash
git add .
git commit -m "v0.0.10 readme.md updated"
git push
```


</details>

---

<div align="center">
  <sub>Built with ❤️ for speed.</sub>
</div>

