#!/bin/bash
set -e

# --- Configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ROOT_DIR="$SCRIPT_DIR/.."
SETTINGS_FILE="$ROOT_DIR/settings.yaml"

# Default work dir if no ID provided (backward compatibility)
WORK_DIR_BASE="/tmp/android_build_env"
WORK_DIR="$WORK_DIR_BASE"

OUTPUT_DIR="$ROOT_DIR/FINISHED_HERE"
SDK_DIR="$WORK_DIR/sdk"
PROJECT_DIR="$WORK_DIR/project"
JDK_DIR="$WORK_DIR/jdk"
GRADLE_DIR="$WORK_DIR/gradle"

# --- Argument Parsing ---
APP_URL=""
APK_FILENAME=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --url) APP_URL="$2"; shift ;;
        --name) APK_FILENAME="$2"; shift ;;
        --id) JOB_ID="$2"; shift ;;
        --no-cleanup) NO_CLEANUP=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# --- Load Settings (Fallback) ---
if [ -z "$APP_URL" ] || [ -z "$APK_FILENAME" ]; then
    if [ -f "$SETTINGS_FILE" ]; then
        [ -z "$APP_URL" ] && APP_URL=$(grep "redirect_to_url" "$SETTINGS_FILE" | cut -d'"' -f2)
        [ -z "$APK_FILENAME" ] && APK_FILENAME=$(grep "apk_name" "$SETTINGS_FILE" | cut -d'"' -f2)
    fi
fi

# Defaults
[ -z "$APP_URL" ] && APP_URL="https://crazywalk.weforks.org/"
[ -z "$APK_FILENAME" ] && APK_FILENAME="CrazyWalk.apk"

APP_NAME="${APK_FILENAME%.apk}"

# If Job ID is present, use unique work dir
if [ -n "$JOB_ID" ]; then
    WORK_DIR="${WORK_DIR_BASE}_${JOB_ID}"
fi

SDK_DIR="$WORK_DIR/sdk"
PROJECT_DIR="$WORK_DIR/project"
JDK_DIR="$WORK_DIR/jdk"
GRADLE_DIR="$WORK_DIR/gradle"

PACKAGE_NAME="org.weforks.crazywalk"
SDK_VERSION="33"
BUILD_TOOLS_VERSION="33.0.1"

# --- OS Detection ---
OS="$(uname -s)"
case "$OS" in
    Linux*)     
        OS_TYPE="linux"
        CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
        JDK_URL="https://aka.ms/download-jdk/microsoft-jdk-17-linux-x64.tar.gz"
        ;;
    Darwin*)    
        OS_TYPE="mac"
        CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip"
        JDK_URL="https://aka.ms/download-jdk/microsoft-jdk-17-mac-x64.tar.gz"
        ;;
    *)          
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

# --- Functions ---

function cleanup() {
    if [ "$NO_CLEANUP" = true ]; then
        echo "Skipping cleanup as requested."
        return
    fi

    echo "Cleaning up..."
    # Kill lingering daemons
    pkill -f "gradle" || true
    pkill -f "java" || true
    pkill -f "adb" || true
    
    sleep 2
    rm -rf "$WORK_DIR"
    echo "Cleanup finished."
}

function download_file() {
    local url="$1"
    local out="$2"
    echo "Downloading $url..."
    curl -L -o "$out" "$url"
}

function extract_file() {
    local file="$1"
    local dest="$2"
    echo "Extracting $file..."
    mkdir -p "$dest"
    if [[ "$file" == *.zip ]]; then
        unzip -q "$file" -d "$dest"
    else
        tar -xf "$file" -C "$dest"
    fi
}

function initialize_java() {
    if java -version 2>&1 | grep -q "17"; then
        echo "Java 17 already installed."
        return
    fi
    
    local jdk_archive="$WORK_DIR/jdk_archive"
    download_file "$JDK_URL" "$jdk_archive"
    extract_file "$jdk_archive" "$WORK_DIR/jdk_temp"
    
    # Find extracted dir
    local extracted_jdk=$(find "$WORK_DIR/jdk_temp" -maxdepth 1 -type d | tail -n 1)
    cp -r "$extracted_jdk" "$JDK_DIR"
    rm -rf "$WORK_DIR/jdk_temp"
    
    export JAVA_HOME="$JDK_DIR"
    export PATH="$JDK_DIR/bin:$PATH"
    
    echo "Java initialized at $JAVA_HOME"
}

function initialize_sdk() {
    mkdir -p "$SDK_DIR"
    local cmdline_tools="$SDK_DIR/cmdline-tools/latest"
    
    if [ ! -f "$cmdline_tools/bin/sdkmanager" ]; then
        local zip="$WORK_DIR/cmdline-tools.zip"
        download_file "$CMDLINE_TOOLS_URL" "$zip"
        
        local temp="$WORK_DIR/cmdline_temp"
        extract_file "$zip" "$temp"
        
        mkdir -p "$(dirname "$cmdline_tools")"
        cp -r "$temp/cmdline-tools" "$cmdline_tools"
        rm -rf "$temp"
    fi
    
    # Licenses
    mkdir -p "$SDK_DIR/licenses"
    echo -e "\n24333f8a63b6825ea9c5514f83c2829b004d1fee" > "$SDK_DIR/licenses/android-sdk-license"
    echo -e "\n84831b9409646a918e30573bab4c9c91346d8abd" >> "$SDK_DIR/licenses/android-sdk-license"
    
    # Install
    echo "Installing Android SDK components..."
    yes | "$cmdline_tools/bin/sdkmanager" --sdk_root="$SDK_DIR" "platform-tools" "platforms;android-$SDK_VERSION" "build-tools;$BUILD_TOOLS_VERSION"
}

function create_project() {
    echo "Creating Android project..."
    rm -rf "$PROJECT_DIR"
    mkdir -p "$PROJECT_DIR/app/src/main/java/org/weforks/crazywalk"
    mkdir -p "$PROJECT_DIR/app/src/main/res/values"
    mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
    mkdir -p "$PROJECT_DIR/app/src/main/res/xml"
    mkdir -p "$PROJECT_DIR/app/src/main/res/mipmap-anydpi-v26"

    # settings.gradle
    cat <<EOF > "$PROJECT_DIR/settings.gradle"
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
rootProject.name = "$APP_NAME"
include ':app'
EOF

    # gradle.properties
    cat <<EOF > "$PROJECT_DIR/gradle.properties"
android.useAndroidX=true
android.enableJetifier=true
EOF

    # build.gradle (Root)
    cat <<EOF > "$PROJECT_DIR/build.gradle"
plugins {
    id 'com.android.application' version '8.1.0' apply false
}
EOF

    # build.gradle (App)
    cat <<EOF > "$PROJECT_DIR/app/build.gradle"
plugins {
    id 'com.android.application'
}
android {
    namespace '$PACKAGE_NAME'
    compileSdk $SDK_VERSION
    defaultConfig {
        applicationId '$PACKAGE_NAME'
        minSdk 24
        targetSdk $SDK_VERSION
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
EOF

    # AndroidManifest.xml
    cat <<EOF > "$PROJECT_DIR/app/src/main/AndroidManifest.xml"
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.INTERNET" />
    <application
        android:allowBackup="true"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        android:icon="@mipmap/ic_launcher"
        android:label="$APP_NAME"
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
EOF

    # Create assets directory
    mkdir -p "$PROJECT_DIR/app/src/main/assets"
    
    # config.properties
    echo "url=$APP_URL" > "$PROJECT_DIR/app/src/main/assets/config.properties"

    # MainActivity.java
    cat <<EOF > "$PROJECT_DIR/app/src/main/java/org/weforks/crazywalk/MainActivity.java"
package $PACKAGE_NAME;
import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import java.io.InputStream;
import java.util.Properties;

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
        
        String url = "$APP_URL"; // Fallback
        try {
            InputStream inputStream = getAssets().open("config.properties");
            Properties properties = new Properties();
            properties.load(inputStream);
            url = properties.getProperty("url", "$APP_URL");
        } catch (Exception e) {
            e.printStackTrace();
        }
        
        myWebView.loadUrl(url);
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
EOF

    # Styles
    cat <<EOF > "$PROJECT_DIR/app/src/main/res/values/styles.xml"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.CrazyWalk" parent="android:Theme.Material.Light.NoActionBar">
        <item name="android:statusBarColor">@android:color/black</item>
    </style>
</resources>
EOF

    # XML Rules
    echo '<data-extraction-rules><cloud-backup><include domain="root" /></cloud-backup></data-extraction-rules>' > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml"
    echo '<full-backup-content><include domain="root" /></full-backup-content>' > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml"

    # Icons (Dummy)
    cat <<EOF > "$PROJECT_DIR/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
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
EOF
    cp "$PROJECT_DIR/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml" "$PROJECT_DIR/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml"
}

function build_apk() {
    cd "$PROJECT_DIR"
    echo "sdk.dir=$SDK_DIR" > local.properties
    
    # Gradle
    local gradle_version="8.3"
    local gradle_zip="$WORK_DIR/gradle.zip"
    if [ ! -f "$WORK_DIR/gradle-$gradle_version/bin/gradle" ]; then
        download_file "https://services.gradle.org/distributions/gradle-$gradle_version-bin.zip" "$gradle_zip"
        extract_file "$gradle_zip" "$WORK_DIR"
    fi
    
    local gradle_cmd="$WORK_DIR/gradle-$gradle_version/bin/gradle"
    chmod +x "$gradle_cmd"
    
    echo "Running Gradle build..."
    echo "PROGRESS: 60"
    "$gradle_cmd" assembleDebug
    
    local apk_path="$PROJECT_DIR/app/build/outputs/apk/debug/app-debug.apk"
    if [ -f "$apk_path" ]; then
        mkdir -p "$OUTPUT_DIR"
        cp "$apk_path" "$OUTPUT_DIR/$APK_FILENAME"
        "$gradle_cmd" --stop > /dev/null 2>&1 || true
        echo "APK Created Successfully: $OUTPUT_DIR/$APK_FILENAME"
        echo "PROGRESS: 100"
    else
        echo "Build failed. APK not found."
        exit 1
    fi
}

# --- Main Execution ---

trap cleanup EXIT

echo "Starting build process..."
echo "PROGRESS: 0"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

initialize_java
echo "PROGRESS: 10"
initialize_sdk
echo "PROGRESS: 40"
create_project
echo "PROGRESS: 50"
build_apk
