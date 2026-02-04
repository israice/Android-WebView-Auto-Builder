param([switch]$NoCleanup)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"; $ProgressPreference = 'SilentlyContinue'

$SettingsPath = "$PSScriptRoot\..\settings.yaml"
if (Test-Path $SettingsPath) { $Settings = Get-Content $SettingsPath; $AppUrl = ($Settings -match "redirect_to_url").Split('"')[1]; $ApkFilename = ($Settings -match "apk_name").Split('"')[1]; $AppName = $ApkFilename.Replace(".apk", "") }
else { $AppUrl = "https://crazywalk.weforks.org/"; $AppName = "CrazyWalk"; $ApkFilename = "CrazyWalk.apk" }
$Namespace = "com.aspect.webview"; $ApplicationId = "com.aspect.app00000000"; $SdkVersion = "33"; $BuildToolsVersion = "33.0.1"
$WorkDir = "$PSScriptRoot\..\android_build_env"; $OutputDir = "$PSScriptRoot\..\FINISHED_HERE"
$SdkDir = "$WorkDir\sdk"; $ProjectDir = "$WorkDir\project"; $JdkDir = "$WorkDir\jdk"; $CurlDir = "$WorkDir\curl"
$CmdLineToolsUrl = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
$JdkUrl = "https://aka.ms/download-jdk/microsoft-jdk-17-windows-x64.zip"
$CurlUrl = "https://curl.se/windows/dl-8.4.0_6/curl-8.4.0_6-win64-mingw.zip"
$JokesFile = "$PSScriptRoot\jokes.txt"
$script:Jokes = if (Test-Path $JokesFile) { Get-Content $JokesFile } else { @("Loading...", "Processing...", "Please wait...") }
$script:LastJokeTime = [DateTime]::MinValue; $script:CurrentJoke = ""; $script:CurrentPercent = 0

function Show-Progress { param($Percent, $Msg)
  $script:CurrentPercent = $Percent; $Now = Get-Date
  if ($Percent -ge 100) { $script:CurrentJoke = "APK Created Successfully!" }
  elseif (($Now - $script:LastJokeTime).TotalSeconds -ge 4) { $script:CurrentJoke = ($script:Jokes | Get-Random) + "... " }
  $script:LastJokeTime = $Now; $W = 50; $F = [Math]::Floor(($Percent/100)*$W); $E = $W - $F
  $C = if ($Percent -ge 100) { "$([char]27)[92m" } else { "$([char]27)[96m" }
  $D = "$([char]27)[90m"; $R = "$([char]27)[0m"; $M = $script:CurrentJoke
  if ($M.Length -gt 40) { $M = $M.Substring(0,37) + "..." }
  Write-Host -NoNewline "`r[$C$('#'*$F)$D$('-'*$E)$R] $Percent% $M       "
}

function Invoke-Cmd { param($File, $Args, $Dir = $PWD)
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = @{ FileName=$File; Arguments=$Args; RedirectStandardOutput=$true; RedirectStandardError=$true; UseShellExecute=$false; CreateNoWindow=$true; WorkingDirectory=$Dir }
  $p.Start() | Out-Null
  while (!$p.HasExited) { $Now = Get-Date; if (($Now - $script:LastJokeTime).TotalSeconds -ge 4 -and $script:CurrentPercent -lt 100) { $script:CurrentJoke = ($script:Jokes | Get-Random) + "... "; $script:LastJokeTime = $Now; Show-Progress $script:CurrentPercent "" }; Start-Sleep -Milliseconds 100 }
  $out = $p.StandardOutput.ReadToEnd() + "`n" + $p.StandardError.ReadToEnd(); $p.WaitForExit()
  @{ ExitCode = $p.ExitCode; Output = $out }
}

function Stop-Procs { $AdbPath = "$PSScriptRoot\android_build_env\sdk\platform-tools\adb.exe"; if (Test-Path $AdbPath) { & $AdbPath kill-server 2>$null }
  Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like "*android_build_env*" -or $_.Name -eq "adb.exe" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue } }

function Remove-Safe { param($Path); if (!(Test-Path $Path)) { return }
  for ($i=0; $i -lt 10; $i++) { try { Remove-Item $Path -Recurse -Force -EA Stop; return } catch { Start-Sleep -Milliseconds 500 } }
  cmd /c "rmdir /s /q `"$Path`"" }

function Clear-Env { if ($PSScriptRoot) { Set-Location $PSScriptRoot }; Stop-Procs; Start-Sleep -Seconds 2; Remove-Safe $WorkDir }

function Wait-Lock { param($Path, $Timeout=30); $sw = [System.Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $Timeout) { try { $s = [System.IO.File]::Open($Path,'Open','Read','None'); if ($s) { $s.Close(); return } } catch { Start-Sleep -Milliseconds 1000 } } }

function Get-File { param($Uri, $Out)
  if (Get-Command "curl.exe" -EA SilentlyContinue) {
    $p = Start-Process -FilePath "curl.exe" -ArgumentList "-L","-o","`"$Out`"","`"$Uri`"","-sS","--connect-timeout","60" -NoNewWindow -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Download failed: curl exit code $($p.ExitCode)" }
  } else { Invoke-WebRequest -Uri $Uri -OutFile $Out -UseBasicParsing }
  Wait-Lock $Out; Unblock-File -Path $Out -EA SilentlyContinue }

function Expand-Zip { param($Path, $Dest, [bool]$Clean = $true)
  if ($Clean -and (Test-Path $Dest)) { Remove-Safe $Dest }; if (!(Test-Path $Dest)) { md $Dest -Force | Out-Null }
  if (Get-Command "tar.exe" -EA SilentlyContinue) { try { $r = Invoke-Cmd "tar.exe" "-xf `"$(Resolve-Path $Path)`" -C `"$(Resolve-Path $Dest)`""; if ($r.ExitCode -eq 0) { return } } catch {} }
  Expand-Archive -Path $Path -DestinationPath $Dest -Force }

function Init-Curl { if (Get-Command "curl.exe" -EA SilentlyContinue) { return }
  Get-File $CurlUrl "$WorkDir\curl.zip"; Expand-Zip "$WorkDir\curl.zip" "$WorkDir\curl_temp"; Start-Sleep 1
  $bin = Get-ChildItem "$WorkDir\curl_temp" -Recurse -Directory | Where-Object { $_.Name -eq "bin" } | Select-Object -First 1
  if ($bin) { if (Test-Path $CurlDir) { Remove-Safe $CurlDir }; Copy-Item $bin.FullName $CurlDir -Recurse -Force; $env:PATH = "$CurlDir;$env:PATH" }
  Remove-Safe "$WorkDir\curl_temp"; Remove-Safe "$WorkDir\curl.zip" }

function Init-Java { try { $null = java -version 2>&1; if ($LASTEXITCODE -eq 0) { return } } catch {}
  Get-File $JdkUrl "$WorkDir\jdk.zip"; Expand-Zip "$WorkDir\jdk.zip" "$WorkDir\jdk_temp"; Start-Sleep 1
  $sub = Get-ChildItem "$WorkDir\jdk_temp" | Select-Object -First 1; if (Test-Path $JdkDir) { Remove-Safe $JdkDir }
  Copy-Item $sub.FullName $JdkDir -Recurse -Force; Remove-Safe "$WorkDir\jdk_temp"; Remove-Safe "$WorkDir\jdk.zip"
  $env:JAVA_HOME = $JdkDir; $env:PATH = "$JdkDir\bin;$env:PATH" }

function Init-Sdk { if (!(Test-Path $SdkDir)) { md $SdkDir -Force | Out-Null }
  $CmdDir = "$SdkDir\cmdline-tools\latest"; $SdkMgr = "$CmdDir\bin\sdkmanager.bat"
  if (!(Test-Path $SdkMgr)) { Get-File $CmdLineToolsUrl "$WorkDir\cmd.zip"; Expand-Zip "$WorkDir\cmd.zip" "$SdkDir\cmd_temp"; Start-Sleep 1
    $bat = Get-ChildItem "$SdkDir\cmd_temp" -Filter "sdkmanager.bat" -Recurse | Select-Object -First 1; if (!$bat) { throw "sdkmanager.bat not found" }
    $root = $bat.Directory.Parent.FullName; if (!(Test-Path "$SdkDir\cmdline-tools")) { md "$SdkDir\cmdline-tools" -Force | Out-Null }
    Copy-Item $root $CmdDir -Recurse -Force; Remove-Safe "$SdkDir\cmd_temp"; Remove-Safe "$WorkDir\cmd.zip" }
  $lic = "$SdkDir\licenses"; if (!(Test-Path $lic)) { md $lic -Force | Out-Null }
  Set-Content "$lic\android-sdk-license" "24333f8a63b6825ea9c5514f83c2829b004d1fee`n84831b9409646a918e30573bab4c9c91346d8abd" -Encoding Ascii
  1..20 | ForEach-Object { "y" } | & $SdkMgr --sdk_root="$SdkDir" "platform-tools" "platforms;android-$SdkVersion" "build-tools;$BuildToolsVersion" | Out-Null }

function New-Project { if (Test-Path $ProjectDir) { Remove-Safe $ProjectDir }
  md "$ProjectDir\app\src\main\java\com\aspect\webview" -Force | Out-Null
  md "$ProjectDir\app\src\main\res\values","$ProjectDir\app\src\main\res\layout","$ProjectDir\app\src\main\res\xml","$ProjectDir\app\src\main\res\mipmap-anydpi-v26","$ProjectDir\app\src\main\assets" -Force | Out-Null
  Set-Content "$ProjectDir\settings.gradle" "pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }`ndependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { google(); mavenCentral() } }`nrootProject.name = `"$AppName`"`ninclude ':app'"
  Set-Content "$ProjectDir\gradle.properties" "android.useAndroidX=true`nandroid.enableJetifier=true"
  Set-Content "$ProjectDir\build.gradle" "plugins { id 'com.android.application' version '8.1.0' apply false }"
  Set-Content "$ProjectDir\app\build.gradle" @"
plugins { id 'com.android.application' }
android { namespace '$Namespace'; compileSdk $SdkVersion
  defaultConfig { applicationId '$ApplicationId'; minSdk 24; targetSdk $SdkVersion; versionCode 1; versionName "1.0" }
  buildTypes { release { minifyEnabled false; proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro' } }
  compileOptions { sourceCompatibility JavaVersion.VERSION_1_8; targetCompatibility JavaVersion.VERSION_1_8 } }
dependencies { implementation 'androidx.appcompat:appcompat:1.6.1'; implementation 'com.google.android.material:material:1.9.0' }
"@
  Set-Content "$ProjectDir\app\src\main\AndroidManifest.xml" @"
<?xml version="1.0" encoding="utf-8"?><manifest xmlns:android="http://schemas.android.com/apk/res/android" xmlns:tools="http://schemas.android.com/tools">
<uses-permission android:name="android.permission.INTERNET"/><uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/><uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/><uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
<application android:allowBackup="true" android:usesCleartextTraffic="true" android:networkSecurityConfig="@xml/network_security_config" android:dataExtractionRules="@xml/data_extraction_rules" android:fullBackupContent="@xml/backup_rules" android:icon="@mipmap/ic_launcher" android:label="$AppName" android:roundIcon="@mipmap/ic_launcher_round" android:supportsRtl="true" android:theme="@style/Theme.WebApp" tools:targetApi="31">
<activity android:name=".MainActivity" android:exported="true" android:configChanges="orientation|screenSize|keyboardHidden" android:theme="@style/Theme.WebApp"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity>
</application></manifest>
"@
  Set-Content "$ProjectDir\app\src\main\assets\config.properties" "url=$AppUrl"
  Set-Content "$ProjectDir\app\src\main\java\com\aspect\webview\MainActivity.java" @"
package $Namespace;
import android.app.Activity; import android.app.AlertDialog; import android.app.DownloadManager;
import android.content.Context; import android.content.pm.PackageManager; import android.graphics.Color;
import android.net.Uri; import android.net.http.SslError; import android.os.Build; import android.os.Bundle;
import android.os.Environment; import android.view.Gravity; import android.view.View; import android.webkit.*;
import android.widget.*; import java.io.InputStream; import java.util.Properties;
public class MainActivity extends Activity {
  private static final int PERMISSION_REQUEST_CODE = 1001;
  private WebView myWebView; private LinearLayout errorLayout; private ProgressBar progressBar; private FrameLayout rootLayout; private String currentUrl;
  private String pendingDownloadUrl; private String pendingUserAgent; private String pendingContentDisposition; private String pendingMimeType;
  @Override protected void onCreate(Bundle savedInstanceState) { super.onCreate(savedInstanceState);
    rootLayout = new FrameLayout(this); rootLayout.setBackgroundColor(Color.WHITE);
    myWebView = new WebView(this); rootLayout.addView(myWebView, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
    progressBar = new ProgressBar(this); FrameLayout.LayoutParams pp = new FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT); pp.gravity = Gravity.CENTER; rootLayout.addView(progressBar, pp);
    createErrorLayout(); setContentView(rootLayout);
    WebSettings ws = myWebView.getSettings(); ws.setJavaScriptEnabled(true); ws.setDomStorageEnabled(true); ws.setDatabaseEnabled(true);
    ws.setCacheMode(WebSettings.LOAD_NO_CACHE); ws.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
    ws.setAllowFileAccess(true); ws.setAllowContentAccess(true); ws.setLoadsImagesAutomatically(true);
    ws.setJavaScriptCanOpenWindowsAutomatically(true); ws.setSupportMultipleWindows(false); ws.setMediaPlaybackRequiresUserGesture(false);
    myWebView.clearCache(true); myWebView.clearHistory();
    myWebView.setWebViewClient(new WebViewClient() {
      @Override public void onPageStarted(WebView v, String u, android.graphics.Bitmap f) { super.onPageStarted(v,u,f); progressBar.setVisibility(View.VISIBLE); errorLayout.setVisibility(View.GONE); myWebView.setVisibility(View.VISIBLE); }
      @Override public void onPageFinished(WebView v, String u) { super.onPageFinished(v,u); progressBar.setVisibility(View.GONE); }
      @Override public void onReceivedError(WebView v, WebResourceRequest r, WebResourceError e) { super.onReceivedError(v,r,e); if (r.isForMainFrame()) showError("Connection Error", "Unable to load the page."); }
      @Override public void onReceivedSslError(WebView v, SslErrorHandler h, SslError e) { new AlertDialog.Builder(MainActivity.this).setTitle("SSL Warning").setMessage("Certificate problem. Continue?").setPositiveButton("Continue", (d,w)->h.proceed()).setNegativeButton("Cancel", (d,w)->{h.cancel();showError("Security Error","SSL failed.");}).setCancelable(false).show(); }
      @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) { v.loadUrl(r.getUrl().toString()); return true; }
    });
    myWebView.setDownloadListener((url, userAgent, contentDisposition, mimeType, contentLength) -> {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && Build.VERSION.SDK_INT <= Build.VERSION_CODES.P) {
        if (checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
          pendingDownloadUrl = url; pendingUserAgent = userAgent; pendingContentDisposition = contentDisposition; pendingMimeType = mimeType;
          requestPermissions(new String[]{android.Manifest.permission.WRITE_EXTERNAL_STORAGE}, PERMISSION_REQUEST_CODE); return; } }
      startDownload(url, userAgent, contentDisposition, mimeType); });
    currentUrl = "$AppUrl"; try { InputStream is = getAssets().open("config.properties"); Properties p = new Properties(); p.load(is); currentUrl = p.getProperty("url", "$AppUrl"); is.close(); } catch (Exception e) {}
    loadUrl(); }
  private void startDownload(String url, String userAgent, String contentDisposition, String mimeType) {
    try { DownloadManager.Request request = new DownloadManager.Request(Uri.parse(url));
      String filename = URLUtil.guessFileName(url, contentDisposition, mimeType);
      request.setMimeType(mimeType); request.addRequestHeader("User-Agent", userAgent);
      request.addRequestHeader("Cookie", CookieManager.getInstance().getCookie(url));
      request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, filename);
      request.allowScanningByMediaScanner(); request.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
      request.setTitle(filename); request.setDescription("Downloading file...");
      DownloadManager dm = (DownloadManager) getSystemService(Context.DOWNLOAD_SERVICE);
      if (dm != null) { dm.enqueue(request); Toast.makeText(this, "Downloading: " + filename, Toast.LENGTH_SHORT).show(); }
    } catch (Exception e) { Toast.makeText(this, "Download failed: " + e.getMessage(), Toast.LENGTH_LONG).show(); } }
  @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults);
    if (requestCode == PERMISSION_REQUEST_CODE) {
      if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
        if (pendingDownloadUrl != null) { startDownload(pendingDownloadUrl, pendingUserAgent, pendingContentDisposition, pendingMimeType); pendingDownloadUrl = null; }
      } else { Toast.makeText(this, "Storage permission required for downloads", Toast.LENGTH_LONG).show(); } } }
  private void createErrorLayout() { errorLayout = new LinearLayout(this); errorLayout.setOrientation(LinearLayout.VERTICAL); errorLayout.setGravity(Gravity.CENTER); errorLayout.setBackgroundColor(Color.WHITE); errorLayout.setVisibility(View.GONE);
    TextView icon = new TextView(this); icon.setText("\u26A0"); icon.setTextSize(64); icon.setGravity(Gravity.CENTER); errorLayout.addView(icon);
    TextView title = new TextView(this); title.setId(android.R.id.title); title.setText("Error"); title.setTextSize(24); title.setTextColor(Color.parseColor("#333333")); title.setGravity(Gravity.CENTER);
    LinearLayout.LayoutParams tp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT); tp.setMargins(0,32,0,16); errorLayout.addView(title, tp);
    TextView msg = new TextView(this); msg.setId(android.R.id.message); msg.setText("Something went wrong"); msg.setTextSize(16); msg.setTextColor(Color.parseColor("#666666")); msg.setGravity(Gravity.CENTER); msg.setPadding(48,0,48,0);
    LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT); mp.setMargins(0,0,0,32); errorLayout.addView(msg, mp);
    Button btn = new Button(this); btn.setText("Retry"); btn.setTextColor(Color.WHITE); btn.setBackgroundColor(Color.parseColor("#2196F3")); btn.setPadding(64,24,64,24); btn.setOnClickListener(v->{ errorLayout.setVisibility(View.GONE); myWebView.setVisibility(View.VISIBLE); loadUrl(); }); errorLayout.addView(btn);
    rootLayout.addView(errorLayout, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)); }
  private void showError(String t, String m) { progressBar.setVisibility(View.GONE); myWebView.setVisibility(View.GONE); TextView et = errorLayout.findViewById(android.R.id.title); TextView em = errorLayout.findViewById(android.R.id.message); if (et!=null) et.setText(t); if (em!=null) em.setText(m); errorLayout.setVisibility(View.VISIBLE); }
  private void loadUrl() { if (currentUrl != null && !currentUrl.isEmpty()) { myWebView.clearCache(true); myWebView.loadUrl(currentUrl); } }
  @Override public void onBackPressed() { if (errorLayout.getVisibility() == View.VISIBLE) finish(); else if (myWebView.canGoBack()) myWebView.goBack(); else super.onBackPressed(); }
  @Override protected void onResume() { super.onResume(); myWebView.onResume(); }
  @Override protected void onPause() { myWebView.onPause(); super.onPause(); }
  @Override protected void onDestroy() { if (myWebView != null) myWebView.destroy(); super.onDestroy(); }
}
"@
  Set-Content "$ProjectDir\app\src\main\res\values\styles.xml" '<?xml version="1.0" encoding="utf-8"?><resources><style name="Theme.WebApp" parent="android:Theme.Material.Light.NoActionBar"><item name="android:statusBarColor">@android:color/black</item></style></resources>'
  Set-Content "$ProjectDir\app\src\main\res\xml\data_extraction_rules.xml" '<?xml version="1.0" encoding="utf-8"?><data-extraction-rules><cloud-backup><include domain="root"/></cloud-backup><device-transfer><include domain="root"/></device-transfer></data-extraction-rules>'
  Set-Content "$ProjectDir\app\src\main\res\xml\backup_rules.xml" '<?xml version="1.0" encoding="utf-8"?><full-backup-content><include domain="root"/></full-backup-content>'
  Set-Content "$ProjectDir\app\src\main\res\xml\network_security_config.xml" '<?xml version="1.0" encoding="utf-8"?><network-security-config><base-config cleartextTrafficPermitted="true"><trust-anchors><certificates src="system"/><certificates src="user"/></trust-anchors></base-config></network-security-config>'
  Set-Content "$ProjectDir\app\src\main\res\mipmap-anydpi-v26\ic_launcher.xml" '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@android:color/holo_blue_light"/><foreground><inset android:inset="20dp"><shape android:shape="oval"><solid android:color="@android:color/white"/></shape></inset></foreground></adaptive-icon>'
  Copy-Item "$ProjectDir\app\src\main\res\mipmap-anydpi-v26\ic_launcher.xml" "$ProjectDir\app\src\main\res\mipmap-anydpi-v26\ic_launcher_round.xml" }

function Build-Apk { Set-Location $ProjectDir; Set-Content "local.properties" "sdk.dir=$($SdkDir -replace '\\','\\')"
  $GradleVer = "8.3"; $GradleDir = "$WorkDir\gradle-$GradleVer"
  if (!(Test-Path "$GradleDir\bin\gradle.bat")) { Get-File "https://services.gradle.org/distributions/gradle-$GradleVer-bin.zip" "$WorkDir\gradle.zip"; Expand-Zip "$WorkDir\gradle.zip" $WorkDir -Clean:$false; Remove-Safe "$WorkDir\gradle.zip" }
  # Run gradle with output redirected to prevent daemon from blocking
  $gradleLog = "$WorkDir\gradle_build.log"
  $p = Start-Process -FilePath "$GradleDir\bin\gradle.bat" -ArgumentList "assembleDebug","--no-daemon" -WorkingDirectory $ProjectDir -RedirectStandardOutput $gradleLog -RedirectStandardError "$WorkDir\gradle_err.log" -Wait -PassThru
  if (Test-Path $gradleLog) { Get-Content $gradleLog -Tail 10 | Write-Host }
  if ($p.ExitCode -eq 0) { $apk = "$ProjectDir\app\build\outputs\apk\debug\app-debug.apk"
    if (Test-Path $apk) { if (!(Test-Path $OutputDir)) { md $OutputDir -Force | Out-Null }; Copy-Item $apk "$OutputDir\$ApkFilename" -Force }
    # Stop Gradle daemon with timeout
    $stopProc = Start-Process -FilePath "$GradleDir\bin\gradle.bat" -ArgumentList "--stop" -WorkingDirectory $ProjectDir -NoNewWindow -PassThru
    if (!$stopProc.WaitForExit(10000)) { $stopProc.Kill() }
    # Kill any remaining Gradle/Java processes from this build
    Get-Process -Name "java" -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "*android_build_env*" } | Stop-Process -Force -ErrorAction SilentlyContinue }
  else { Write-Error "Build Failed. Gradle exit code: $($p.ExitCode)" } }

try { Show-Progress 0 "Starting..."; Clear-Env; Show-Progress 5 "Cleaning..."
  if (!(Test-Path $WorkDir)) { md $WorkDir -Force | Out-Null }
  Show-Progress 10 "Curl..."; Init-Curl
  Show-Progress 20 "Java..."; Init-Java
  Show-Progress 40 "SDK..."; Init-Sdk
  Show-Progress 60 "Project..."; New-Project
  Show-Progress 70 "Building..."; Build-Apk
} catch { Write-Host ""; Write-Error $_.Exception.Message }
finally { if (!$NoCleanup) { Show-Progress 95 "Cleanup..."; Clear-Env } else { Show-Progress 95 "Skip cleanup..." }; Show-Progress 100 "Finished."; Write-Host "" }
