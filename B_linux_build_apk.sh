#!/bin/bash
set -e

# Configuration
if [ -f "settings.yaml" ]; then
    APP_URL=$(grep "redirect_to_url" settings.yaml | cut -d'"' -f2)
    APK_FILENAME=$(grep "apk_name" settings.yaml | cut -d'"' -f2)
    APP_NAME="${APK_FILENAME%.apk}"
    echo "Loaded settings from settings.yaml"
    echo "  URL: $APP_URL"
    echo "  APK: $APK_FILENAME"
else
    echo "settings.yaml not found! Using defaults."
    APP_URL="https://crazywalk.weforks.org/"
    APP_NAME="CrazyWalk"
    APK_FILENAME="CrazyWalk.apk"
fi
PACKAGE_NAME="org.weforks.crazywalk"
SDK_VERSION="33"
BUILD_TOOLS_VERSION="33.0.1"
WORK_DIR="$(pwd)/android_build_env"
SDK_DIR="$WORK_DIR/sdk"
PROJECT_DIR="$WORK_DIR/project"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
JDK_URL="https://aka.ms/download-jdk/microsoft-jdk-17-linux-x64.tar.gz"
JDK_DIR="$WORK_DIR/jdk"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
    echo -e "${CYAN}[$(date +'%H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}Error: $1${NC}"
    exit 1
}

# --- Helper Functions ---

check_dependencies() {
    log "Checking dependencies..."
    if ! command -v curl &> /dev/null; then
        error "curl is required but not installed. Please install it (e.g., sudo apt install curl)."
    fi
    if ! command -v unzip &> /dev/null; then
        error "unzip is required but not installed. Please install it (e.g., sudo apt install unzip)."
    fi
}

setup_java() {
    if command -v java &> /dev/null; then
        # Check version (simple check)
        JAVA_VER=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2 | cut -d'.' -f1)
        if [ "$JAVA_VER" -ge 17 ]; then
            log "System Java found (Version $JAVA_VER)."
            return
        fi
    fi

    if [ -d "$JDK_DIR/bin" ]; then
        log "Portable Java found."
        export JAVA_HOME="$JDK_DIR"
        export PATH="$JDK_DIR/bin:$PATH"
        return
    fi

    log "Java 17+ not found. Downloading Portable OpenJDK 17..."
    mkdir -p "$WORK_DIR"
    curl -L -o "$WORK_DIR/jdk.tar.gz" "$JDK_URL"
    sleep 1 # Wait for file system sync
    
    log "Extracting Java..."
    mkdir -p "$JDK_DIR"
    tar -xzf "$WORK_DIR/jdk.tar.gz" -C "$JDK_DIR" --strip-components=1
    rm "$WORK_DIR/jdk.tar.gz"

    export JAVA_HOME="$JDK_DIR"
    export PATH="$JDK_DIR/bin:$PATH"
    log "Portable Java installed."
}

setup_sdk() {
    if [ ! -d "$SDK_DIR/cmdline-tools/latest/bin" ]; then
        log "Downloading Android Command Line Tools..."
        mkdir -p "$WORK_DIR"
        curl -L -o "$WORK_DIR/cmdline-tools.zip" "$CMDLINE_TOOLS_URL"
        
        log "Extracting tools..."
        mkdir -p "$SDK_DIR/cmdline-tools"
        unzip -q "$WORK_DIR/cmdline-tools.zip" -d "$SDK_DIR/cmdline-tools"
        
        # Handle folder structure (cmdline-tools/cmdline-tools -> cmdline-tools/latest)
        if [ -d "$SDK_DIR/cmdline-tools/cmdline-tools" ]; then
            mv "$SDK_DIR/cmdline-tools/cmdline-tools" "$SDK_DIR/cmdline-tools/latest"
        else
            # Fallback if extracted directly
            mkdir -p "$SDK_DIR/cmdline-tools/latest"
            mv "$SDK_DIR/cmdline-tools/bin" "$SDK_DIR/cmdline-tools/latest/"
            mv "$SDK_DIR/cmdline-tools/lib" "$SDK_DIR/cmdline-tools/latest/"
            if [ -d "$SDK_DIR/cmdline-tools/source.properties" ]; then
                mv "$SDK_DIR/cmdline-tools/source.properties" "$SDK_DIR/cmdline-tools/latest/"
            fi
        fi
        
        rm "$WORK_DIR/cmdline-tools.zip"
    fi

    SDKMANAGER="$SDK_DIR/cmdline-tools/latest/bin/sdkmanager"
    
    # Accept Licenses
    log "Accepting licenses..."
    mkdir -p "$SDK_DIR/licenses"
    echo -e "24333f8a63b6825ea9c5514f83c2829b004d1fee\n84831b9409646a918e30573bab4c9c91346d8abd" > "$SDK_DIR/licenses/android-sdk-license"
    
    # Install Components
    log "Installing SDK components..."
    yes | "$SDKMANAGER" --sdk_root="$SDK_DIR" "platform-tools" "platforms;android-$SDK_VERSION" "build-tools;$BUILD_TOOLS_VERSION" > /dev/null
}

generate_project() {
    log "Generating Android Project Structure..."
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

    # MainActivity.java
    cat <<EOF > "$PROJECT_DIR/app/src/main/java/org/weforks/crazywalk/MainActivity.java"
package $PACKAGE_NAME;

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
        myWebView.loadUrl("$APP_URL");
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
    cat <<EOF > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml"
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup><include domain="root" /></cloud-backup>
    <device-transfer><include domain="root" /></device-transfer>
</data-extraction-rules>
EOF
    cat <<EOF > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml"
<?xml version="1.0" encoding="utf-8"?>
<full-backup-content><include domain="root" /></full-backup-content>
EOF

    # Icons
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

build_apk() {
    log "Initializing Gradle..."
    cd "$PROJECT_DIR"
    
    # local.properties
    echo "sdk.dir=$SDK_DIR" > local.properties

    # Download Gradle
    GRADLE_VERSION="8.3"
    if [ ! -f "$WORK_DIR/gradle-$GRADLE_VERSION/bin/gradle" ]; then
        log "Downloading Gradle $GRADLE_VERSION..."
        curl -L -o "$WORK_DIR/gradle.zip" "https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip"
        unzip -q "$WORK_DIR/gradle.zip" -d "$WORK_DIR"
        rm "$WORK_DIR/gradle.zip"
    fi
    GRADLE_CMD="$WORK_DIR/gradle-$GRADLE_VERSION/bin/gradle"
    chmod +x "$GRADLE_CMD"

    log "Building APK (AssembleDebug)..."
    "$GRADLE_CMD" assembleDebug

    if [ -f "$PROJECT_DIR/app/build/outputs/apk/debug/app-debug.apk" ]; then
        echo -e "${GREEN}Build Success!${NC}"
        cp "$PROJECT_DIR/app/build/outputs/apk/debug/app-debug.apk" "../../$APK_FILENAME"
        echo -e "${GREEN}APK created at: $(pwd)/../../$APK_FILENAME${NC}"
        
        # Cleanup
        # Cleanup
        log "Cleaning up build environment..."
        
        # Step out of the directory to avoid locking it (though less of an issue on Linux, good practice)
        cd ../..
        
        if [ -f "./BA_linux_clean_build_folder_manualy.sh" ]; then
            chmod +x ./BA_linux_clean_build_folder_manualy.sh
            ./BA_linux_clean_build_folder_manualy.sh
        else
            # Fallback
            pkill -f "$WORK_DIR" || true
            sleep 2
            rm -rf "$WORK_DIR"
            echo -e "${GREEN}Build environment removed.${NC}"
        fi
    else
        error "Build failed. APK not found."
    fi
}

# --- Main Execution ---

check_dependencies
setup_java
setup_sdk
generate_project
build_apk
