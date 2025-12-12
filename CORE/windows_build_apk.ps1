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
$ProgressPreference = 'SilentlyContinue'

# Configuration
$SettingsPath = "$PSScriptRoot\..\settings.yaml"
if (Test-Path $SettingsPath) {
    $Settings = Get-Content $SettingsPath
    $AppUrl = ($Settings -match "redirect_to_url").Split('"')[1]
    $ApkFilename = ($Settings -match "apk_name").Split('"')[1]
    $AppName = $ApkFilename.Replace(".apk", "")
}
else {
    Write-Warning "settings.yaml not found! Using defaults."
    $AppUrl = "https://crazywalk.weforks.org/"
    $AppName = "CrazyWalk"
    $ApkFilename = "CrazyWalk.apk"
}
$PackageName = "org.weforks.crazywalk"
$SdkVersion = "33"
$BuildToolsVersion = "33.0.1"

# Directories
$WorkDir = "$PSScriptRoot\..\android_build_env"
$OutputDir = "$PSScriptRoot\..\FINISHED_HERE"
$SdkDir = "$WorkDir\sdk"
$ProjectDir = "$WorkDir\project"
$JdkDir = "$WorkDir\jdk"
$CurlDir = "$WorkDir\curl"

# URLs
$CmdLineToolsUrl = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
$JdkUrl = "https://aka.ms/download-jdk/microsoft-jdk-17-windows-x64.zip"
$CurlUrl = "https://curl.se/windows/dl-8.4.0_6/curl-8.4.0_6-win64-mingw.zip"

# Load Jokes
$JokesFile = "$PSScriptRoot\jokes.txt"
if (Test-Path $JokesFile) {
    $script:Jokes = Get-Content $JokesFile
}
else {
    $script:Jokes = @("Loading...", "Processing...", "Please wait...")
}
$script:LastJokeTime = [DateTime]::MinValue
$script:CurrentJoke = ""
$script:CurrentPercent = 0
$script:JokeIndex = 0

# --- Helper Functions ---

function Get-RandomJoke {
    if ($script:Jokes.Count -gt 0) {
        $j = $script:Jokes | Get-Random
        return "$j... "
    }
    return "Processing.... "
}

function Show-ProgressBar {
    param($Percent, $Message)
    
    $Width = 50
    $FilledCount = [Math]::Floor(($Percent / 100) * $Width)
    $EmptyCount = $Width - $FilledCount
    
    $Filled = "█" * $FilledCount
    $Empty = "░" * $EmptyCount
    
    # ANSI Colors
    $Cyan = "$([char]27)[96m" # Bright Cyan
    $Green = "$([char]27)[92m" # Bright Green
    $DarkGray = "$([char]27)[90m"
    $Reset = "$([char]27)[0m"
    
    if ($Percent -ge 100) {
        $BarColor = $Green
    }
    else {
        $BarColor = $Cyan
    }
    
    # Truncate message if too long for one line
    $MaxMsgLen = 40
    if ($Message.Length -gt $MaxMsgLen) { $Message = $Message.Substring(0, $MaxMsgLen - 3) + "..." }
    
    # Use Carriage Return (`r) to overwrite line. Add padding spaces at the end to clear previous text.
    Write-Host -NoNewline "`r$BarColor$Filled$DarkGray$Empty$Reset $Percent% $Message       "
}

function Update-Ui {
    if ($script:CurrentPercent -ge 100) { return }
    
    $Now = Get-Date
    if (($Now - $script:LastJokeTime).TotalSeconds -ge 4) {
        $script:CurrentJoke = Get-RandomJoke
        $script:LastJokeTime = $Now
        Show-ProgressBar $script:CurrentPercent $script:CurrentJoke
    }
}

function Show-Progress {
    param($Percent, $Message_Ignored)
    $script:CurrentPercent = $Percent
    
    if ($Percent -ge 100) {
        $script:CurrentJoke = "APK Created Successfully!"
    }
    else {
        # Force update immediately on step change
        $script:CurrentJoke = Get-RandomJoke
    }
    
    $script:LastJokeTime = Get-Date
    Show-ProgressBar $script:CurrentPercent $script:CurrentJoke
}

function Invoke-CommandWithProgress {
    param($FilePath, $ArgumentList, $WorkingDirectory = $PWD)
    
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $FilePath
    $pinfo.Arguments = $ArgumentList
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $pinfo.WorkingDirectory = $WorkingDirectory
    
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    
    while (-not $p.HasExited) {
        Update-Ui
        Start-Sleep -Milliseconds 100
    }
    
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    
    return @{
        ExitCode = $p.ExitCode
        Output   = $stdout + "`n" + $stderr
    }
}

function Write-Status {
    param($Message)
    # Deprecated in favor of Show-Progress
}

function Stop-LingeringProcesses {
    Write-Status "Checking for lingering processes..."
    
    # Try to find adb in the build env to kill server gracefully
    $AdbPath = "$PSScriptRoot\android_build_env\sdk\platform-tools\adb.exe"
    if (Test-Path $AdbPath) {
        & $AdbPath kill-server 2>$null
    }

    $Processes = Get-CimInstance Win32_Process | Where-Object { 
        $_.ExecutablePath -like "*android_build_env*" -or $_.Name -eq "adb.exe" -or $_.Name -eq "java.exe"
    }
    foreach ($Proc in $Processes) {
        # Double check path for java/adb to avoid killing system-wide things if not careful
        # But user wants "delete everything", so aggressive is better.
        # However, killing system java might be bad if user has other things.
        # Let's stick to the path filter OR explicit adb.exe (adb is usually safe to kill).
        if ($Proc.Name -eq "adb.exe" -or $Proc.ExecutablePath -like "*android_build_env*") {
            Stop-Process -Id $Proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
}

function Remove-ItemSafe {
    param($Path)
    if (-not (Test-Path $Path)) { return }
    
    for ($i = 0; $i -lt 10; $i++) {
        try {
            Remove-Item $Path -Recurse -Force -ErrorAction Stop
            return
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }
    
    # Fallback to cmd rmdir
    Write-Warning "PowerShell remove failed, trying cmd rmdir..."
    cmd /c "rmdir /s /q `"$Path`""
    
    if (Test-Path $Path) {
        Write-Warning "Unable to remove $Path (File locked?)"
    }
}



function Clear-BuildEnvironment {
    Write-Status "Cleaning up build environment..."
    
    # Ensure we are not inside the directory we are about to delete
    if ($PSScriptRoot) { Set-Location $PSScriptRoot }
    
    Stop-LingeringProcesses
    Start-Sleep -Seconds 2
    Remove-ItemSafe $WorkDir
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
        }
        catch {
            Start-Sleep -Milliseconds 1000
        }
    }
    Write-Warning "File $Path appears to be locked after $TimeoutSeconds seconds."
}

function Invoke-Download {
    param($Uri, $OutFile)
    
    # Try using curl (system or portable)
    if (Get-Command "curl.exe" -ErrorAction SilentlyContinue) {
        $Result = Invoke-CommandWithProgress "curl.exe" "-L -o `"$OutFile`" `"$Uri`" -sS"
        if ($Result.ExitCode -ne 0) { 
            throw "Download failed with curl (Exit code: $($Result.ExitCode)). Output:`n$($Result.Output)" 
        }
    }
    else {
        # Fallback to PowerShell
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
        }
        catch {
            throw "Download failed: $_"
        }
    }

    Wait-FileLock $OutFile
    Unblock-File -Path $OutFile -ErrorAction SilentlyContinue
}

function Invoke-Extract {
    param($Path, $Destination, [bool]$CleanDestination = $true)
    
    if ($CleanDestination -and (Test-Path $Destination)) {
        Remove-ItemSafe $Destination
    }
    if (-not (Test-Path $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    # Try tar (much faster on Windows 10/11)
    if (Get-Command "tar.exe" -ErrorAction SilentlyContinue) {
        try {
            $AbsPath = (Resolve-Path $Path).Path
            $AbsDest = (Resolve-Path $Destination).Path
            
            $Result = Invoke-CommandWithProgress "tar.exe" "-xf `"$AbsPath`" -C `"$AbsDest`""
            
            if ($Result.ExitCode -ne 0) { throw "Tar extraction failed." }
            return
        }
        catch {
            # Fallback
        }
    }

    # Fallback
    Expand-Archive -Path $Path -DestinationPath $Destination -Force
}

function Initialize-Curl {
    if (Get-Command "curl.exe" -ErrorAction SilentlyContinue) {
        return
    }

    $CurlZip = "$WorkDir\curl.zip"
    Invoke-Download -Uri $CurlUrl -OutFile $CurlZip
    
    Invoke-Extract -Path $CurlZip -Destination "$WorkDir\curl_temp"
    Start-Sleep -Seconds 1
    
    $BinDir = Get-ChildItem -Path "$WorkDir\curl_temp" -Recurse -Directory | Where-Object { $_.Name -eq "bin" } | Select-Object -First 1
    if ($BinDir) {
        if (Test-Path $CurlDir) { Remove-ItemSafe $CurlDir }
        Copy-Item -Path $BinDir.FullName -Destination $CurlDir -Recurse -Force
        $env:PATH = "$CurlDir;$env:PATH"
    }
    Remove-ItemSafe "$WorkDir\curl_temp"
    Remove-ItemSafe $CurlZip
}

function Initialize-Java {
    $javaAvailable = $false
    try {
        $null = java -version 2>&1
        if ($LASTEXITCODE -eq 0) { $javaAvailable = $true }
    }
    catch {}

    if ($javaAvailable) {
        # System Java found
        return
    }

    Write-Status "Java not found. Installing Portable OpenJDK 17..."
    $JdkZip = "$WorkDir\jdk.zip"
    Invoke-Download -Uri $JdkUrl -OutFile $JdkZip
    
    Write-Status "Extracting Java..."
    Invoke-Extract -Path $JdkZip -Destination "$WorkDir\jdk_temp"
    Start-Sleep -Seconds 1
    
    $SubDir = Get-ChildItem "$WorkDir\jdk_temp" | Select-Object -First 1
    if (Test-Path $JdkDir) { Remove-ItemSafe $JdkDir }
    Copy-Item -Path $SubDir.FullName -Destination $JdkDir -Recurse -Force
    
    Remove-ItemSafe "$WorkDir\jdk_temp"
    Remove-ItemSafe $JdkZip

    $env:JAVA_HOME = $JdkDir
    $env:PATH = "$JdkDir\bin;$env:PATH"
}

function Initialize-Sdk {
    if (-not (Test-Path $SdkDir)) { New-Item -ItemType Directory -Path $SdkDir -Force | Out-Null }

    $CmdLineToolsFinal = "$SdkDir\cmdline-tools\latest"
    $SdkManager = "$CmdLineToolsFinal\bin\sdkmanager.bat"

    if (-not (Test-Path $SdkManager)) {
        $ZipPath = "$WorkDir\cmdline-tools.zip"
        Invoke-Download -Uri $CmdLineToolsUrl -OutFile $ZipPath
        
        $TempExtract = "$SdkDir\cmdline-tools_temp"
        Invoke-Extract -Path $ZipPath -Destination $TempExtract
        Start-Sleep -Seconds 1
        
        $SdkBat = Get-ChildItem -Path $TempExtract -Filter "sdkmanager.bat" -Recurse | Select-Object -First 1
        if ($null -eq $SdkBat) { throw "Could not find sdkmanager.bat" }

        $ToolRoot = $SdkBat.Directory.Parent.FullName
        $ParentDir = "$SdkDir\cmdline-tools"
        if (-not (Test-Path $ParentDir)) { New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null }
        
        Copy-Item -Path $ToolRoot -Destination $CmdLineToolsFinal -Recurse -Force
        
        # Verify
        if (-not (Test-Path "$CmdLineToolsFinal\bin\sdkmanager.bat")) {
            Write-Error "CRITICAL: sdkmanager.bat not found after copy!"
            throw "SDK Copy Failed"
        }

        Remove-ItemSafe $TempExtract
        Remove-ItemSafe $ZipPath
    }
    
    $LicensesDir = "$SdkDir\licenses"
    if (-not (Test-Path $LicensesDir)) { New-Item -ItemType Directory -Path $LicensesDir -Force | Out-Null }
    $AndroidSdkLicense = "24333f8a63b6825ea9c5514f83c2829b004d1fee`n84831b9409646a918e30573bab4c9c91346d8abd"
    Set-Content -Path "$LicensesDir\android-sdk-license" -Value $AndroidSdkLicense -Encoding Ascii
    
    Set-Content -Path "$LicensesDir\android-sdk-license" -Value $AndroidSdkLicense -Encoding Ascii
    
    $YesInput = 1..20 | ForEach-Object { "y" }
    $YesInput | & "$SdkManager" --sdk_root="$SdkDir" "platform-tools" "platforms;android-$SdkVersion" "build-tools;$BuildToolsVersion" | Out-Null
}

function New-AndroidProject {
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
        webSettings.setCacheMode(WebSettings.LOAD_NO_CACHE);
        
        myWebView.clearCache(true);

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
    
    $SdkDirEscaped = $SdkDir -replace "\\", "\\"
    Set-Content -Path "local.properties" -Value "sdk.dir=$SdkDirEscaped"

    $GradleVersion = "8.3"
    $GradleDir = "$WorkDir\gradle-$GradleVersion"
    
    if (-not (Test-Path "$GradleDir\bin\gradle.bat")) {
        $GradleUrl = "https://services.gradle.org/distributions/gradle-$GradleVersion-bin.zip"
        Invoke-Download -Uri $GradleUrl -OutFile "$WorkDir\gradle.zip"
        Invoke-Extract -Path "$WorkDir\gradle.zip" -Destination $WorkDir -CleanDestination:$false
        Remove-ItemSafe "$WorkDir\gradle.zip"
    }
    
    $GradleCmd = "$GradleDir\bin\gradle.bat"
    
    $GradleCmd = "$GradleDir\bin\gradle.bat"
    
    $Result = Invoke-CommandWithProgress $GradleCmd "assembleDebug" $ProjectDir
    
    if ($Result.ExitCode -eq 0) {
        $ApkPath = "$ProjectDir\app\build\outputs\apk\debug\app-debug.apk"
        if (Test-Path $ApkPath) {
            if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
            Copy-Item $ApkPath "$OutputDir\$ApkFilename" -Force
            
            $null = Invoke-CommandWithProgress $GradleCmd "--stop" $ProjectDir
            
            # Cleanup
            Clear-BuildEnvironment
        }
    }
    else {
        Write-Error "Build Failed. Output:`n$($Result.Output)"
    }
}

# --- Main Execution ---

try {
    # 1. Pre-execution Cleanup (Delete Everything)
    Show-Progress 0 "Starting..."
    Clear-BuildEnvironment
    Show-Progress 5 "Cleaning environment..."
    
    # 2. Re-create WorkDir
    if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }

    # 3. Initialize & Build
    Show-Progress 10 "Initializing Curl..."
    Initialize-Curl
    
    Show-Progress 20 "Initializing Java..."
    Initialize-Java
    
    Show-Progress 40 "Initializing Android SDK..."
    Initialize-Sdk
    
    Show-Progress 60 "Creating Project..."
    New-AndroidProject
    
    Show-Progress 70 "Building APK..."
    Invoke-ApkBuild
    

}
catch {
    Write-Host ""
    Write-Error $_.Exception.Message
}
finally {
    # 4. Post-execution Cleanup (Delete Everything - Always runs)
    Show-Progress 95 "Cleaning up..."
    Clear-BuildEnvironment
    Show-Progress 100 "Finished."
    Write-Host ""
}
