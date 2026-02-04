#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR="$SCRIPT_DIR/.." && SETTINGS_FILE="$ROOT_DIR/settings.yaml"
WORK_DIR_BASE="$ROOT_DIR/android_build_env" && WORK_DIR="$WORK_DIR_BASE"
OUTPUT_DIR="$ROOT_DIR/FINISHED_HERE"
while [[ $# -gt 0 ]]; do case $1 in --url) APP_URL=$2;shift;; --name) APK_FILENAME=$2;shift;; --id) JOB_ID=$2;shift;; --no-cleanup) NO_CLEANUP=1;; *) echo "Unknown: $1";exit 1;; esac;shift;done
if [ -z "$APP_URL" ] || [ -z "$APK_FILENAME" ]; then
    [ -f "$SETTINGS_FILE" ] && { [ -z "$APP_URL" ] && APP_URL=$(grep "redirect_to_url" "$SETTINGS_FILE"|cut -d'"' -f2); [ -z "$APK_FILENAME" ] && APK_FILENAME=$(grep "apk_name" "$SETTINGS_FILE"|cut -d'"' -f2); }
fi
[ -z "$APP_URL" ] && APP_URL="https://crazywalk.weforks.org/"
[ -z "$APK_FILENAME" ] && APK_FILENAME="CrazyWalk.apk"
APP_NAME="${APK_FILENAME%.apk}"
[ -n "$JOB_ID" ] && WORK_DIR="${WORK_DIR_BASE}_${JOB_ID}"
SDK_DIR="$WORK_DIR/sdk" && PROJECT_DIR="$WORK_DIR/project" && JDK_DIR="$WORK_DIR/jdk"
PACKAGE_NAME="org.weforks.crazywalk" && SDK_VERSION="33" && BUILD_TOOLS_VERSION="33.0.1"
OS="$(uname -s)"
case "$OS" in
    Linux*) OS_TYPE="linux"; CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"; JDK_URL="https://aka.ms/download-jdk/microsoft-jdk-17-linux-x64.tar.gz";;
    Darwin*) OS_TYPE="mac"; CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip"; JDK_URL="https://aka.ms/download-jdk/microsoft-jdk-17-mac-x64.tar.gz";;
    *) echo "Unsupported OS: $OS"; exit 1;;
esac
cleanup() { [ "$NO_CLEANUP" = 1 ] && return; pkill -f "gradle" 2>/dev/null||true; pkill -f "java" 2>/dev/null||true; pkill -f "adb" 2>/dev/null||true; sleep 2; rm -rf "$WORK_DIR"; }
fetch() { local u=$1 o=$2 d=$3; curl -sL "$u" -o "$o"; mkdir -p "$d"; [[ "$o" == *.zip ]] && unzip -oq "$o" -d "$d" || tar -xf "$o" -C "$d"; }
initialize_java() {
    java -version 2>&1|grep -q "17" && return
    fetch "$JDK_URL" "$WORK_DIR/jdk_archive" "$WORK_DIR/jdk_temp"
    cp -r "$(find "$WORK_DIR/jdk_temp" -maxdepth 1 -type d|tail -n1)" "$JDK_DIR"; rm -rf "$WORK_DIR/jdk_temp"
    export JAVA_HOME="$JDK_DIR" PATH="$JDK_DIR/bin:$PATH"
}
initialize_sdk() {
    mkdir -p "$SDK_DIR"; local cmdline_tools="$SDK_DIR/cmdline-tools/latest"
    if [ ! -f "$cmdline_tools/bin/sdkmanager" ]; then
        fetch "$CMDLINE_TOOLS_URL" "$WORK_DIR/cmdline-tools.zip" "$WORK_DIR/cmdline_temp"
        mkdir -p "$(dirname "$cmdline_tools")"; cp -r "$WORK_DIR/cmdline_temp/cmdline-tools" "$cmdline_tools"; rm -rf "$WORK_DIR/cmdline_temp"
    fi
    mkdir -p "$SDK_DIR/licenses"; printf '\n24333f8a63b6825ea9c5514f83c2829b004d1fee\n\n84831b9409646a918e30573bab4c9c91346d8abd\n' > "$SDK_DIR/licenses/android-sdk-license"
    yes | "$cmdline_tools/bin/sdkmanager" --sdk_root="$SDK_DIR" "platform-tools" "platforms;android-$SDK_VERSION" "build-tools;$BUILD_TOOLS_VERSION"
}
create_project() {
    rm -rf "$PROJECT_DIR"
    mkdir -p "$PROJECT_DIR/app/src/main/"{java/org/weforks/crazywalk,res/{values,layout,xml,mipmap-anydpi-v26},assets}
    cat <<EOF > "$PROJECT_DIR/settings.gradle"
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { google(); mavenCentral() } }
rootProject.name = "$APP_NAME"
include ':app'
EOF
    echo -e "android.useAndroidX=true\nandroid.enableJetifier=true" > "$PROJECT_DIR/gradle.properties"
    echo "plugins { id 'com.android.application' version '8.1.0' apply false }" > "$PROJECT_DIR/build.gradle"
    cat <<EOF > "$PROJECT_DIR/app/build.gradle"
plugins { id 'com.android.application' }
android {
    namespace '$PACKAGE_NAME'
    compileSdk $SDK_VERSION
    defaultConfig { applicationId '$PACKAGE_NAME'; minSdk 24; targetSdk $SDK_VERSION; versionCode 1; versionName "1.0" }
    buildTypes { release { minifyEnabled false; proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro' } }
    compileOptions { sourceCompatibility JavaVersion.VERSION_1_8; targetCompatibility JavaVersion.VERSION_1_8 }
}
dependencies { implementation 'androidx.appcompat:appcompat:1.6.1'; implementation 'com.google.android.material:material:1.9.0' }
EOF
    cat <<EOF > "$PROJECT_DIR/app/src/main/AndroidManifest.xml"
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.INTERNET"/><uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <application android:allowBackup="true" android:usesCleartextTraffic="true" android:networkSecurityConfig="@xml/network_security_config" android:dataExtractionRules="@xml/data_extraction_rules" android:fullBackupContent="@xml/backup_rules" android:icon="@mipmap/ic_launcher" android:label="$APP_NAME" android:roundIcon="@mipmap/ic_launcher_round" android:supportsRtl="true" android:theme="@style/Theme.CrazyWalk" tools:targetApi="31">
        <activity android:name=".MainActivity" android:exported="true" android:configChanges="orientation|screenSize|keyboardHidden" android:theme="@style/Theme.CrazyWalk">
            <intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter>
        </activity>
    </application>
</manifest>
EOF
    echo "url=$APP_URL" > "$PROJECT_DIR/app/src/main/assets/config.properties"
    cat <<EOF > "$PROJECT_DIR/app/src/main/java/org/weforks/crazywalk/MainActivity.java"
package $PACKAGE_NAME;
import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Color;
import android.net.http.SslError;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.webkit.*;
import android.widget.*;
import java.io.InputStream;
import java.util.Properties;
public class MainActivity extends Activity {
    private WebView myWebView; private LinearLayout errorLayout; private ProgressBar progressBar; private FrameLayout rootLayout; private String currentUrl;
    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        rootLayout = new FrameLayout(this); rootLayout.setBackgroundColor(Color.WHITE);
        myWebView = new WebView(this);
        rootLayout.addView(myWebView, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        progressBar = new ProgressBar(this);
        FrameLayout.LayoutParams pp = new FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT);
        pp.gravity = Gravity.CENTER; rootLayout.addView(progressBar, pp);
        createErrorLayout(); setContentView(rootLayout);
        WebSettings ws = myWebView.getSettings();
        ws.setJavaScriptEnabled(true); ws.setDomStorageEnabled(true); ws.setDatabaseEnabled(true); ws.setCacheMode(WebSettings.LOAD_NO_CACHE);
        ws.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW); ws.setAllowFileAccess(true); ws.setAllowContentAccess(true);
        ws.setLoadsImagesAutomatically(true); ws.setJavaScriptCanOpenWindowsAutomatically(true); ws.setSupportMultipleWindows(false); ws.setMediaPlaybackRequiresUserGesture(false);
        myWebView.clearCache(true); myWebView.clearHistory();
        myWebView.setWebViewClient(new WebViewClient() {
            @Override public void onPageStarted(WebView v, String u, android.graphics.Bitmap f) { super.onPageStarted(v,u,f); progressBar.setVisibility(View.VISIBLE); errorLayout.setVisibility(View.GONE); myWebView.setVisibility(View.VISIBLE); }
            @Override public void onPageFinished(WebView v, String u) { super.onPageFinished(v,u); progressBar.setVisibility(View.GONE); }
            @Override public void onReceivedError(WebView v, WebResourceRequest r, WebResourceError e) { super.onReceivedError(v,r,e); if(r.isForMainFrame()) showError("Connection Error","Unable to load. Check internet."); }
            @Override public void onReceivedSslError(WebView v, SslErrorHandler h, SslError e) {
                new AlertDialog.Builder(MainActivity.this).setTitle("SSL Warning").setMessage("Certificate problem. Continue?")
                    .setPositiveButton("Continue",(d,w)->h.proceed()).setNegativeButton("Cancel",(d,w)->{h.cancel();showError("Security Error","SSL failed.");}).setCancelable(false).show();
            }
            @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) { v.loadUrl(r.getUrl().toString()); return true; }
        });
        currentUrl = "$APP_URL";
        try { InputStream is = getAssets().open("config.properties"); Properties p = new Properties(); p.load(is); currentUrl = p.getProperty("url","$APP_URL"); is.close(); } catch(Exception e) {}
        loadUrl();
    }
    private void createErrorLayout() {
        errorLayout = new LinearLayout(this); errorLayout.setOrientation(LinearLayout.VERTICAL); errorLayout.setGravity(Gravity.CENTER);
        errorLayout.setBackgroundColor(Color.WHITE); errorLayout.setVisibility(View.GONE);
        TextView ei = new TextView(this); ei.setText("\u26A0"); ei.setTextSize(64); ei.setGravity(Gravity.CENTER); errorLayout.addView(ei);
        TextView et = new TextView(this); et.setId(android.R.id.title); et.setText("Error"); et.setTextSize(24); et.setTextColor(Color.parseColor("#333333")); et.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams tp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,LinearLayout.LayoutParams.WRAP_CONTENT); tp.setMargins(0,32,0,16); errorLayout.addView(et,tp);
        TextView em = new TextView(this); em.setId(android.R.id.message); em.setText("Something went wrong"); em.setTextSize(16); em.setTextColor(Color.parseColor("#666666")); em.setGravity(Gravity.CENTER); em.setPadding(48,0,48,0);
        LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,LinearLayout.LayoutParams.WRAP_CONTENT); mp.setMargins(0,0,0,32); errorLayout.addView(em,mp);
        Button rb = new Button(this); rb.setText("Retry"); rb.setTextColor(Color.WHITE); rb.setBackgroundColor(Color.parseColor("#2196F3")); rb.setPadding(64,24,64,24);
        rb.setOnClickListener(v->{ errorLayout.setVisibility(View.GONE); myWebView.setVisibility(View.VISIBLE); loadUrl(); }); errorLayout.addView(rb);
        rootLayout.addView(errorLayout, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT,FrameLayout.LayoutParams.MATCH_PARENT));
    }
    private void showError(String t, String m) {
        progressBar.setVisibility(View.GONE); myWebView.setVisibility(View.GONE);
        TextView et=errorLayout.findViewById(android.R.id.title), em=errorLayout.findViewById(android.R.id.message);
        if(et!=null)et.setText(t); if(em!=null)em.setText(m); errorLayout.setVisibility(View.VISIBLE);
    }
    private void loadUrl() { if(currentUrl!=null&&!currentUrl.isEmpty()){ myWebView.clearCache(true); myWebView.loadUrl(currentUrl); } }
    @Override public void onBackPressed() { if(errorLayout.getVisibility()==View.VISIBLE) finish(); else if(myWebView.canGoBack()) myWebView.goBack(); else super.onBackPressed(); }
    @Override protected void onResume() { super.onResume(); myWebView.onResume(); }
    @Override protected void onPause() { myWebView.onPause(); super.onPause(); }
    @Override protected void onDestroy() { if(myWebView!=null) myWebView.destroy(); super.onDestroy(); }
}
EOF
    echo '<?xml version="1.0" encoding="utf-8"?><resources><style name="Theme.CrazyWalk" parent="android:Theme.Material.Light.NoActionBar"><item name="android:statusBarColor">@android:color/black</item></style></resources>' > "$PROJECT_DIR/app/src/main/res/values/styles.xml"
    echo '<data-extraction-rules><cloud-backup><include domain="root"/></cloud-backup></data-extraction-rules>' > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml"
    echo '<full-backup-content><include domain="root"/></full-backup-content>' > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml"
    echo '<?xml version="1.0" encoding="utf-8"?><network-security-config><base-config cleartextTrafficPermitted="true"><trust-anchors><certificates src="system"/><certificates src="user"/></trust-anchors></base-config></network-security-config>' > "$PROJECT_DIR/app/src/main/res/xml/network_security_config.xml"
    cat <<'EOF' > "$PROJECT_DIR/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@android:color/holo_blue_light"/><foreground><inset android:inset="20dp"><shape android:shape="oval"><solid android:color="@android:color/white"/></shape></inset></foreground></adaptive-icon>
EOF
    cp "$PROJECT_DIR/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml" "$PROJECT_DIR/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml"
}
build_apk() {
    cd "$PROJECT_DIR"; echo "sdk.dir=$SDK_DIR" > local.properties
    local gv="8.3" gz="$WORK_DIR/gradle.zip"
    [ ! -f "$WORK_DIR/gradle-$gv/bin/gradle" ] && { curl -sL "https://services.gradle.org/distributions/gradle-$gv-bin.zip" -o "$gz"; mkdir -p "$WORK_DIR"; unzip -oq "$gz" -d "$WORK_DIR"; }
    local gc="$WORK_DIR/gradle-$gv/bin/gradle"; chmod +x "$gc"
    echo "PROGRESS: 60"; "$gc" assembleDebug
    local apk="$PROJECT_DIR/app/build/outputs/apk/debug/app-debug.apk"
    if [ -f "$apk" ]; then mkdir -p "$OUTPUT_DIR"; cp "$apk" "$OUTPUT_DIR/$APK_FILENAME"; "$gc" --stop 2>/dev/null||true; echo "APK: $OUTPUT_DIR/$APK_FILENAME"; echo "PROGRESS: 100"
    else echo "Build failed"; exit 1; fi
}
trap cleanup EXIT
echo "PROGRESS: 0"
[ -n "$JOB_ID" ] && rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
initialize_java; echo "PROGRESS: 10"
initialize_sdk; echo "PROGRESS: 40"
create_project; echo "PROGRESS: 50"
build_apk
