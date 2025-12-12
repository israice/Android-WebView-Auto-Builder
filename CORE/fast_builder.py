import os
import shutil
import subprocess
import requests
import time
import tempfile
import glob
from xml.etree import ElementTree as ET

class FastApkBuilder:
    def __init__(self, core_dir):
        self.core_dir = core_dir
        self.apktool_jar = os.path.join(core_dir, "apktool.jar")
        self.template_dir = os.path.join(core_dir, "apk_template")
        self.keystore_path = os.path.join(core_dir, "debug.keystore")
        self.is_windows = os.name == 'nt'
        
        # Match the shell script's work dir
        # Linux/Mac: /tmp/android_build_env
        # Windows: %TEMP%\android_build_env (usually) or relative to script
        # The Windows script uses "$PSScriptRoot\..\android_build_env" which is relative to CORE
        # CORE is at c:\0_PROJECTS\android-webview-redirect\CORE
        # So work dir is c:\0_PROJECTS\android-webview-redirect\android_build_env
        
        if self.is_windows:
             self.work_dir_base = os.path.abspath(os.path.join(core_dir, "..", "android_build_env"))
        else:
             self.work_dir_base = os.path.join(tempfile.gettempdir(), "android_build_env")
             
        self.sdk_dir = os.path.join(self.work_dir_base, "sdk")
        self.jdk_dir = os.path.join(self.work_dir_base, "jdk")

    def _get_java_cmd(self):
        # Try to find the Java installed by the shell script
        java_bin = os.path.join(self.jdk_dir, "bin", "java.exe" if self.is_windows else "java")
        if os.path.exists(java_bin):
            return java_bin
        # Fallback to system java
        return "java"

    def _get_build_tool(self, tool_name):
        # Find build-tools in SDK
        build_tools_dir = os.path.join(self.sdk_dir, "build-tools")
        if os.path.exists(build_tools_dir):
            versions = sorted(os.listdir(build_tools_dir))
            if versions:
                latest = versions[-1]
                # Check for .exe or .bat on Windows
                if self.is_windows:
                    if not tool_name.endswith(".exe") and not tool_name.endswith(".bat"):
                        # Try adding extensions
                        for ext in [".exe", ".bat"]:
                            path = os.path.join(build_tools_dir, latest, tool_name + ext)
                            if os.path.exists(path):
                                return path
                
                tool_path = os.path.join(build_tools_dir, latest, tool_name)
                if os.path.exists(tool_path):
                    return tool_path
        return None

    def prepare_environment(self):
        """Ensures apktool and template exist."""
        # 1. Download Apktool if missing
        if not os.path.exists(self.apktool_jar):
            print("Downloading apktool.jar...")
            url = "https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.9.1.jar"
            response = requests.get(url, allow_redirects=True)
            with open(self.apktool_jar, 'wb') as f:
                f.write(response.content)
        
        # 2. Generate Template if missing (This also downloads Java if needed)
        # We also check if zipalign exists. In Docker, the template might exist (copied from host)
        # but the SDK (in /tmp) might be missing.
        zipalign = self._get_build_tool("zipalign")
        
        if not os.path.exists(self.template_dir) or not zipalign:
            print("Generating APK Template (and restoring SDK)...")
            self._create_template()

        # 3. Generate Keystore if missing
        if not os.path.exists(self.keystore_path):
            print("Generating debug keystore...")
            # Refresh Java path in case it was just downloaded
            keytool = os.path.join(self.jdk_dir, "bin", "keytool.exe" if self.is_windows else "keytool")
            
            if not os.path.exists(keytool):
                # Try system keytool
                keytool = "keytool"
            
            try:
                subprocess.run([
                    keytool, "-genkey", "-v", "-keystore", self.keystore_path,
                    "-storepass", "android", "-alias", "androiddebugkey",
                    "-keypass", "android", "-keyalg", "RSA", "-keysize", "2048",
                    "-validity", "10000", "-dname", "CN=Android Debug,O=Android,C=US"
                ], check=False, shell=self.is_windows) 
            except Exception as e:
                print(f"Warning: Failed to generate keystore: {e}")

    def _create_template(self):
        # Run the shell script to build a base APK
        if self.is_windows:
            script_path = os.path.join(self.core_dir, "windows_build_apk.ps1")
            # Pass -NoCleanup to keep the environment (Java/SDK) for future builds
            cmd = ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", script_path, "-NoCleanup"]
            
            # Windows script reads settings.yaml, so we might need to temporarily modify it or pass args if supported
            # The Windows script DOES NOT support args like --url yet. It reads settings.yaml.
            # I should update Windows script to support args OR write a temp settings.yaml.
            # Writing temp settings.yaml is easier.
            settings_path = os.path.join(self.core_dir, "..", "settings.yaml")
            original_settings = None
            if os.path.exists(settings_path):
                with open(settings_path, 'r') as f: original_settings = f.read()
            
            with open(settings_path, 'w') as f:
                f.write('redirect_to_url: "TEMPLATE_URL"\napk_name: "Template.apk"')
                
            try:
                subprocess.run(cmd, check=True)
            finally:
                if original_settings:
                    with open(settings_path, 'w') as f: f.write(original_settings)
        else:
            script_path = os.path.join(self.core_dir, "linux_mac_build_apk.sh")
            os.chmod(script_path, 0o755)
            subprocess.run([
                script_path, 
                "--url", "TEMPLATE_URL", 
                "--name", "Template.apk",
                "--no-cleanup"
            ], check=True)
        
        # Find the output APK
        output_dir = os.path.join(os.path.dirname(self.core_dir), "FINISHED_HERE")
        apk_path = os.path.join(output_dir, "Template.apk")
        
        if not os.path.exists(apk_path):
            raise Exception("Template build failed: APK not found")
            
        # Decompile
        print("Decompiling template...")
        java = self._get_java_cmd()
        subprocess.run([
            java, "-jar", self.apktool_jar, 
            "d", "-f", "-o", self.template_dir, apk_path
        ], check=True)
        
        print("Template created successfully.")

    def build(self, url, app_name, job_id, progress_callback=None):
        """
        Builds an APK by patching the template.
        """
        if progress_callback: progress_callback(10)
        
        # Create temp dir for this job
        job_dir = os.path.join(self.work_dir_base, f"job_{job_id}")
        if os.path.exists(job_dir):
            shutil.rmtree(job_dir)
        shutil.copytree(self.template_dir, job_dir)
        
        if progress_callback: progress_callback(30)
        
        try:
            # 1. Patch URL (assets/config.properties)
            config_path = os.path.join(job_dir, "assets", "config.properties")
            # Ensure assets dir exists (it should from template)
            os.makedirs(os.path.dirname(config_path), exist_ok=True)
            with open(config_path, "w") as f:
                f.write(f"url={url}")
                
            # 2. Patch App Name (res/values/strings.xml)
            # Apktool decodes resources, so we look for strings.xml
            # Note: Path might vary slightly depending on apktool version/resource config
            # We'll search for it.
            strings_path = None
            for root, dirs, files in os.walk(os.path.join(job_dir, "res")):
                if "strings.xml" in files:
                    # Check if it contains app_name
                    path = os.path.join(root, "strings.xml")
                    with open(path, 'r', encoding='utf-8') as f:
                        if 'name="app_name"' in f.read():
                            strings_path = path
                            break
            
            if strings_path:
                tree = ET.parse(strings_path)
                root = tree.getroot()
                for string in root.findall('string'):
                    if string.get('name') == 'app_name':
                        string.text = app_name
                        break
                tree.write(strings_path, encoding='utf-8', xml_declaration=True)
            
            if progress_callback: progress_callback(50)
            
            # 3. Build APK
            java = self._get_java_cmd()
            unsigned_apk = os.path.join(self.work_dir_base, f"unsigned_{job_id}.apk")
            
            cmd = [java, "-jar", self.apktool_jar, "b", job_dir, "-o", unsigned_apk]
            subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
            if progress_callback: progress_callback(70)
            
            # 4. Zipalign
            zipalign = self._get_build_tool("zipalign")
            if not zipalign:
                raise Exception("zipalign not found in SDK")
                
            aligned_apk = os.path.join(self.work_dir_base, f"aligned_{job_id}.apk")
            subprocess.run([zipalign, "-f", "-v", "4", unsigned_apk, aligned_apk], 
                           check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
            if progress_callback: progress_callback(80)
            
            # 5. Sign
            apksigner = self._get_build_tool("apksigner")
            if not apksigner:
                # Try finding apksigner.bat or shell script
                apksigner = self._get_build_tool("apksigner.bat") 
            
            if not apksigner:
                 raise Exception("apksigner not found in SDK")

            final_apk_name = app_name if app_name.endswith(".apk") else f"{app_name}.apk"
            output_dir = os.path.join(os.path.dirname(self.core_dir), "FINISHED_HERE")
            final_apk_path = os.path.join(output_dir, final_apk_name)
            
            # apksigner needs a shell wrapper usually, or call java -jar apksigner.jar
            # If it's a script, call it directly.
            
            env = os.environ.copy()
            if os.path.exists(os.path.join(self.jdk_dir, "bin")):
                env["JAVA_HOME"] = self.jdk_dir
                env["PATH"] = os.path.join(self.jdk_dir, "bin") + os.pathsep + env["PATH"]
            
            subprocess.run([
                apksigner, "sign", "--ks", self.keystore_path,
                "--ks-pass", "pass:android",
                "--out", final_apk_path,
                aligned_apk
            ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
            
            if progress_callback: progress_callback(100)
            
            return final_apk_path
            
        finally:
            # Cleanup
            if os.path.exists(job_dir):
                shutil.rmtree(job_dir)
            if os.path.exists(f"unsigned_{job_id}.apk"):
                os.remove(f"unsigned_{job_id}.apk")
            if os.path.exists(f"aligned_{job_id}.apk"):
                os.remove(f"aligned_{job_id}.apk")
