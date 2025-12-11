<#
.SYNOPSIS
    Automated Android APK Builder for WebView
    
.DESCRIPTION
    This script downloads the necessary Android SDK Command Line Tools,
    sets up a minimal Android project, and builds a debug APK.
    
    It automatically handles dependencies:
    - Curl (for faster downloads)
    - Java (OpenJDK 17)
    - Android SDK & Build Tools
    - Gradle
    
.NOTES
    Author: Antigravity
    Date: 2025-12-11
#>

$ErrorActionPreference = "Stop"

# Configuration
$SettingsPath = "$PSScriptRoot\settings.yaml"
if (Test-Path $SettingsPath) {
    $Settings = Get-Content $SettingsPath
    $AppUrl = ($Settings -match "redirect_to_url").Split('"')[1]
    $ApkFilename = ($Settings -match "apk_name").Split('"')[1]
    $AppName = $ApkFilename.Replace(".apk", "")
    Write-Host "Loaded settings from settings.yaml" -ForegroundColor Cyan
    Write-Host "  URL: $AppUrl" -ForegroundColor Gray
    Write-Host "  APK: $ApkFilename" -ForegroundColor Gray
} else {
    Write-Warning "settings.yaml not found! Using defaults."
    $AppUrl = "https://crazywalk.weforks.org/"
    $AppName = "CrazyWalk"
    $ApkFilename = "CrazyWalk.apk"
}
$PackageName = "org.weforks.crazywalk"
$SdkVersion = "33"
$BuildToolsVersion = "33.0.1"
$WorkDir = "$PSScriptRoot\android_build_env"
$SdkDir = "$WorkDir\sdk"
$ProjectDir = "$WorkDir\project"
$CmdLineToolsUrl = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
$JdkUrl = "https://aka.ms/download-jdk/microsoft-jdk-17-windows-x64.zip"
$JdkDir = "$WorkDir\jdk"
# Using a specific version of curl for stability
$CurlUrl = "https://curl.se/windows/dl-8.4.0_6/curl-8.4.0_6-win64-mingw.zip"
$CurlDir = "$WorkDir\curl"

# --- Helper Functions ---

function Write-Status {
    param([string]$Message)
    Write-Host -ForegroundColor Cyan "`n[$((Get-Date).ToString('HH:mm:ss'))] $Message"
}

function Invoke-Download {
    param($Uri, $OutFile)
    
    # Try using curl (system or portable)
    if (Get-Command "curl.exe" -ErrorAction SilentlyContinue) {
        Write-Host "Downloading with curl..." -ForegroundColor DarkGray
        & curl.exe -L -o "$OutFile" "$Uri"
        if ($LASTEXITCODE -ne 0) { 
            throw "Download failed with curl (Exit code: $LASTEXITCODE). If you cancelled, this is expected." 
        }
        Wait-FileLock $OutFile
        Unblock-File -Path $OutFile -ErrorAction SilentlyContinue
        return
    }

    # Fallback to optimized Invoke-WebRequest
    $origProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Write-Host "Downloading with PowerShell (Progress bar disabled for speed)..." -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
        Wait-FileLock $OutFile
        Unblock-File -Path $OutFile -ErrorAction SilentlyContinue
    }
    finally {
        $ProgressPreference = $origProgress
    }
}

function Invoke-Extract {
    param($Path, $Destination)
    
    if (Test-Path $Destination) {
        Remove-ItemSafe $Destination
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    # Try tar (much faster on Windows 10/11)
    if (Get-Command "tar.exe" -ErrorAction SilentlyContinue) {
        Write-Host "Extracting with tar..." -ForegroundColor DarkGray
        try {
            $AbsPath = (Resolve-Path $Path).Path
            $AbsDest = (Resolve-Path $Destination).Path
            & tar.exe -xf "$AbsPath" -C "$AbsDest"
            if ($LASTEXITCODE -ne 0) { throw "Tar extraction failed." }
            return
        }
        catch {
            Write-Warning "Tar failed, falling back to Expand-Archive..."
        }
    }

    # Fallback
    Write-Host "Extracting with PowerShell..." -ForegroundColor DarkGray
    Write-Warning "Unable to remove $Path (File locked?)"
}

function Remove-ItemSafe {
    param($Path)
    if (-not (Test-Path $Path)) { return }
    
    for ($i = 0; $i -lt 10; $i++) {
        try {
            Remove-Item $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }
    Write-Warning "Unable to remove $Path (File locked?)"
}

function Wait-FileLock {
    param($Path, $TimeoutSeconds = 30)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            # Try to open the file with exclusive access to check if it's locked
            $stream = [System.IO.File]::Open($Path, 'Open', 'Read', 'None')
            if ($stream) {
                $stream.Close()
                return
            }
        } catch {
            Write-Host "Waiting for file lock on $Path..." -ForegroundColor DarkGray
            Start-Sleep -Milliseconds 1000
        }
    }
    Write-Warning "File $Path appears to be locked after $TimeoutSeconds seconds."
}

function Initialize-Curl {
    if (Get-Command "curl.exe" -ErrorAction SilentlyContinue) {
        return
    }

    Write-Status "Curl not found. Installing portable Curl for speed..."
    
    if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
    $CurlZip = "$WorkDir\curl.zip"
    
    # Download using PowerShell (one-time slow download to get the fast tool)
    $origProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $CurlUrl -OutFile $CurlZip -UseBasicParsing
    }
    finally {
        $ProgressPreference = $origProgress
    }
    
    Wait-FileLock $CurlZip

    Invoke-Extract -Path $CurlZip -Destination "$WorkDir\curl_temp"
    
    # Find the bin folder
    $BinDir = Get-ChildItem -Path "$WorkDir\curl_temp" -Recurse -Directory | Where-Object { $_.Name -eq "bin" } | Select-Object -First 1
    
    if ($BinDir) {
        if (Test-Path $CurlDir) { Remove-Item $CurlDir -Recurse -Force }
        Move-Item $BinDir.FullName $CurlDir
        
        # Add to PATH for this session
        $env:PATH = "$CurlDir;$env:PATH"
        Write-Host "Portable Curl installed." -ForegroundColor Green
    }
    
    Remove-ItemSafe "$WorkDir\curl_temp"
    Remove-ItemSafe $CurlZip
}

function Initialize-Java {
    Write-Status "Checking for Java..."
    $javaAvailable = $false
    try {
        $null = java -version 2>&1
        if ($LASTEXITCODE -eq 0) { $javaAvailable = $true }
    }
    catch {}

    if ($javaAvailable) {
        Write-Host "System Java found." -ForegroundColor Green
        return
    }

    # Check local JDK
    if (Test-Path "$JdkDir\bin\java.exe") {
        Write-Status "Found portable Java. Setting up environment..."
        $env:JAVA_HOME = $JdkDir
        $env:PATH = "$JdkDir\bin;$env:PATH"
        return
    }

    # Download JDK
    if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
    Write-Status "Java not found. Downloading Portable OpenJDK 17..."
    $JdkZip = "$WorkDir\jdk.zip"
    Invoke-Download -Uri $JdkUrl -OutFile $JdkZip
    
    Write-Status "Extracting Java..."
    Invoke-Extract -Path $JdkZip -Destination "$WorkDir\jdk_temp"
    
    # Move inner folder to $JdkDir
    $SubDir = Get-ChildItem "$WorkDir\jdk_temp" | Select-Object -First 1
    if (Test-Path $JdkDir) { Remove-ItemSafe $JdkDir }
    Move-Item $SubDir.FullName $JdkDir
    Remove-ItemSafe "$WorkDir\jdk_temp"
    Remove-ItemSafe $JdkZip

    # Set Env
    $env:JAVA_HOME = $JdkDir
    $env:PATH = "$JdkDir\bin;$env:PATH"
    
    Write-Host "Portable Java installed and configured." -ForegroundColor Green
}

function Initialize-Sdk {
    if (-not (Test-Path $SdkDir)) {
        New-Item -ItemType Directory -Path $SdkDir -Force | Out-Null
    }

    $CmdLineToolsFinal = "$SdkDir\cmdline-tools\latest"
    $SdkManager = "$CmdLineToolsFinal\bin\sdkmanager.bat"

    if (-not (Test-Path $SdkManager)) {
        Write-Status "Downloading Android Command Line Tools..."
        $ZipPath = "$WorkDir\cmdline-tools.zip"
        Invoke-Download -Uri $CmdLineToolsUrl -OutFile $ZipPath
        
        Write-Status "Extracting tools..."
        # Extract to a temp folder to inspect structure
        $TempExtract = "$SdkDir\cmdline-tools_temp"
        if (Test-Path $TempExtract) { Remove-Item $TempExtract -Recurse -Force }
        Invoke-Extract -Path $ZipPath -Destination $TempExtract
        
        # Find sdkmanager.bat to determine root
        $SdkBat = Get-ChildItem -Path $TempExtract -Filter "sdkmanager.bat" -Recurse | Select-Object -First 1
        
        if ($null -eq $SdkBat) {
            throw "Could not find sdkmanager.bat in the downloaded zip."
        }

        # We want the parent of the 'bin' folder.
        # SdkBat is .../Something/bin/sdkmanager.bat
        # We want .../Something
        $ToolRoot = $SdkBat.Directory.Parent.FullName
        
        Write-Status "Found tools at: $ToolRoot"
        
        # Move to correct location: cmdline-tools/latest
        if (Test-Path $CmdLineToolsFinal) { Remove-ItemSafe $CmdLineToolsFinal }
        
        # Ensure parent cmdline-tools exists
        $ParentDir = "$SdkDir\cmdline-tools"
        if (-not (Test-Path $ParentDir)) { New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null }
        
        Move-Item -Path $ToolRoot -Destination $CmdLineToolsFinal
        
        # Cleanup
        Remove-ItemSafe $TempExtract
        Remove-ItemSafe $ZipPath
    }
    
    # Create licenses directory and file to avoid prompts (CI/CD standard approach)
    $LicensesDir = "$SdkDir\licenses"
    if (-not (Test-Path $LicensesDir)) { New-Item -ItemType Directory -Path $LicensesDir -Force | Out-Null }
    
    # Common license hashes
    $AndroidSdkLicense = "24333f8a63b6825ea9c5514f83c2829b004d1fee`n84831b9409646a918e30573bab4c9c91346d8abd"
    Set-Content -Path "$LicensesDir\android-sdk-license" -Value $AndroidSdkLicense -Encoding Ascii
    
    Write-Status "Accepting licenses..."
    # Pipe 'y' multiple times to sdkmanager just in case
    $YesInput = 1..20 | ForEach-Object { "y" }
    $YesInput | & "$SdkManager" --sdk_root="$SdkDir" --licenses | Out-Null

    Write-Status "Installing SDK components (Platform $SdkVersion, Build-Tools $BuildToolsVersion)..."
    # Also pipe 'y' to the install command to be safe
    $YesInput | & "$SdkManager" --sdk_root="$SdkDir" "platform-tools" "platforms;android-$SdkVersion" "build-tools;$BuildToolsVersion"
}

function New-AndroidProject {
    Write-Status "Generating Android Project Structure..."
    
    if (Test-Path $ProjectDir) { Remove-ItemSafe $ProjectDir }
    New-Item -ItemType Directory -Path "$ProjectDir\app\src\main\java\org\weforks\crazywalk" -Force | Out-Null
    New-Item -ItemType Directory -Path "$ProjectDir\app\src\main\res\values" -Force | Out-Null
    New-Item -ItemType Directory -Path "$ProjectDir\app\src\main\res\layout" -Force | Out-Null

    # 1. settings.gradle
    Set-Content -Path "$ProjectDir\settings.gradle" -Value @"
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "$AppName"
include ':app'
"@

    # 1.5 gradle.properties
    Set-Content -Path "$ProjectDir\gradle.properties" -Value @"
android.useAndroidX=true
android.enableJetifier=true
"@

    # 2. build.gradle (Root)
    Set-Content -Path "$ProjectDir\build.gradle" -Value @"
plugins {
    id 'com.android.application' version '8.1.0' apply false
}
"@

    # 3. build.gradle (App)
    Set-Content -Path "$ProjectDir\app\build.gradle" -Value @"
plugins {
    id 'com.android.application'
}

android {
    namespace '$PackageName'
    compileSdk $SdkVersion

    defaultConfig {
        applicationId '$PackageName'
        minSdk 24
        targetSdk $SdkVersion
        versionCode 1
        versionName "1.0"
    }

    buildTypes {
        release {
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
}

dependencies {
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'com.google.android.material:material:1.9.0'
}
"@

    # 4. AndroidManifest.xml
    Set-Content -Path "$ProjectDir\app\src\main\AndroidManifest.xml" -Value @"
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.INTERNET" />

    <application
        android:allowBackup="true"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        android:icon="@mipmap/ic_launcher"
        android:label="$AppName"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.CrazyWalk"
        tools:targetApi="31">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:theme="@style/Theme.CrazyWalk">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
"@

    # 5. MainActivity.java
    Set-Content -Path "$ProjectDir\app\src\main\java\org\weforks\crazywalk\MainActivity.java" -Value @"
package $PackageName;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

public class MainActivity extends Activity {
    private WebView myWebView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        myWebView = new WebView(this);
        setContentView(myWebView);

        WebSettings webSettings = myWebView.getSettings();
        webSettings.setJavaScriptEnabled(true);
        webSettings.setDomStorageEnabled(true);

        myWebView.setWebViewClient(new WebViewClient());
        myWebView.loadUrl("$AppUrl");
    }

    @Override
    public void onBackPressed() {
        if (myWebView.canGoBack()) {
            myWebView.goBack();
        } else {
            super.onBackPressed();
        }
    }
}
"@

    # 6. Styles (No Action Bar)
    Set-Content -Path "$ProjectDir\app\src\main\res\values\styles.xml" -Value @"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.CrazyWalk" parent="android:Theme.Material.Light.NoActionBar">
        <item name="android:statusBarColor">@android:color/black</item>
    </style>
</resources>
"@

    # 7. Dummy XML rules to prevent build errors
    New-Item -ItemType Directory -Path "$ProjectDir\app\src\main\res\xml" -Force | Out-Null
    Set-Content -Path "$ProjectDir\app\src\main\res\xml\data_extraction_rules.xml" -Value @"
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup><include domain="root" /></cloud-backup>
    <device-transfer><include domain="root" /></device-transfer>
</data-extraction-rules>
"@
    Set-Content -Path "$ProjectDir\app\src\main\res\xml\backup_rules.xml" -Value @"
<?xml version="1.0" encoding="utf-8"?>
<full-backup-content><include domain="root" /></full-backup-content>
"@

    # 8. Icons
    New-Item -ItemType Directory -Path "$ProjectDir\app\src\main\res\mipmap-anydpi-v26" -Force | Out-Null
    Set-Content -Path "$ProjectDir\app\src\main\res\mipmap-anydpi-v26\ic_launcher.xml" -Value @"
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@android:color/holo_blue_light"/>
    <foreground>
        <inset android:inset="20dp">
             <shape android:shape="oval">
                 <solid android:color="@android:color/white"/>
             </shape>
        </inset>
    </foreground>
</adaptive-icon>
"@
    Copy-Item "$ProjectDir\app\src\main\res\mipmap-anydpi-v26\ic_launcher.xml" "$ProjectDir\app\src\main\res\mipmap-anydpi-v26\ic_launcher_round.xml"
}

function Invoke-ApkBuild {
    Write-Status "Initializing Gradle..."
    Set-Location $ProjectDir
    
    # Create local.properties with sdk.dir
    $SdkDirEscaped = $SdkDir -replace "\\", "\\"
    Set-Content -Path "local.properties" -Value "sdk.dir=$SdkDirEscaped"

    $GradleVersion = "8.3"
    $GradleDir = "$WorkDir\gradle-$GradleVersion"
    if (-not (Test-Path "$GradleDir\bin\gradle.bat")) {
        Write-Status "Downloading Gradle $GradleVersion..."
        $GradleUrl = "https://services.gradle.org/distributions/gradle-$GradleVersion-bin.zip"
        Invoke-Download -Uri $GradleUrl -OutFile "$WorkDir\gradle.zip"
        Invoke-Extract -Path "$WorkDir\gradle.zip" -Destination $WorkDir
        Remove-ItemSafe "$WorkDir\gradle.zip"
    }
    
    $GradleCmd = "$GradleDir\bin\gradle.bat"
    
    Write-Status "Building APK (AssembleDebug)..."
    & "$GradleCmd" assembleDebug
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Build Success!" -ForegroundColor Green
        $ApkPath = "$ProjectDir\app\build\outputs\apk\debug\app-debug.apk"
        if (Test-Path $ApkPath) {
            Copy-Item $ApkPath "$PSScriptRoot\$ApkFilename" -Force
            Write-Host "APK created at: $PSScriptRoot\$ApkFilename" -ForegroundColor Green
            
            # Cleanup
            Write-Status "Cleaning up build environment..."
            
            # Reset location to script root to release directory lock
            Set-Location $PSScriptRoot
            
            if (Test-Path "$PSScriptRoot\AA_windows_clean_build_folder_manualy.ps") {
                & "$PSScriptRoot\AA_windows_clean_build_folder_manualy.ps"
            } else {
                # Fallback if AA_windows_clean_build_folder_manualy.ps is missing
                if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
            }
        }
    }
    else {
        Write-Error "Build Failed. Check output above."
    }
}

# --- Main Execution ---

try {
    Initialize-Curl
    Initialize-Java
    Initialize-Sdk
    New-AndroidProject
    Invoke-ApkBuild
}
catch {
    Write-Error $_.Exception.Message
}
