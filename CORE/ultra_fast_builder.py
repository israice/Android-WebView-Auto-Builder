import os
import shutil
import subprocess
import zipfile
import tempfile

class UltraFastBuilder:
    PLACEHOLDER_NAME = "PLACEHOLDER_APP_NAME__________________________" # 50 chars

    def __init__(self, core_dir):
        self.core_dir = core_dir
        self.template_dir = os.path.join(core_dir, "apk_template_ultra") # Separate template dir
        self.keystore_path = os.path.join(core_dir, "debug.keystore")
        self.is_windows = os.name == 'nt'
        
        # Match the shell script's work dir logic
        if self.is_windows:
             self.work_dir_base = os.path.abspath(os.path.join(core_dir, "..", "android_build_env"))
        else:
             self.work_dir_base = os.path.join(tempfile.gettempdir(), "android_build_env")
             
        self.sdk_dir = os.path.join(self.work_dir_base, "sdk")
        self.jdk_dir = os.path.join(self.work_dir_base, "jdk")

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
        """Ensures template exists with the PLACEHOLDER name."""
        # Check if template APK exists
        output_dir = os.path.join(os.path.dirname(self.core_dir), "FINISHED_HERE")
        template_apk = os.path.join(output_dir, "TemplateUltra.apk")
        
        zipalign = self._get_build_tool("zipalign")

        if not os.path.exists(template_apk) or not zipalign:
            print("Generating Ultra Fast Template...")
            self._create_template()

    def _create_template(self):
        # Reuse the existing build scripts but pass the PLACEHOLDER name
        if self.is_windows:
            script_path = os.path.join(self.core_dir, "windows_build_apk.ps1")
            
            # Modify settings.yaml temporarily
            settings_path = os.path.join(self.core_dir, "..", "settings.yaml")
            original_settings = None
            if os.path.exists(settings_path):
                with open(settings_path, 'r') as f: original_settings = f.read()
            
            with open(settings_path, 'w') as f:
                f.write(f'redirect_to_url: "TEMPLATE_URL"\napk_name: "TemplateUltra.apk"')
            
            # We also need to inject the placeholder name into the build script logic
            # Since the Windows script reads from settings.yaml, we can't easily pass the App Name *string* 
            # (it derives it from apk_name). 
            # Actually, the Windows script does: $AppName = $ApkFilename.Replace(".apk", "")
            # So if apk_name is "TemplateUltra.apk", AppName is "TemplateUltra".
            # We need AppName to be the PLACEHOLDER.
            
            # Let's write a specific settings file that forces the App Name if possible, 
            # OR we modify the script to accept an override.
            # Easier: Just use the placeholder as the filename for the template build!
            
            placeholder_filename = self.PLACEHOLDER_NAME + ".apk"
            
            with open(settings_path, 'w') as f:
                f.write(f'redirect_to_url: "TEMPLATE_URL"\napk_name: "{placeholder_filename}"')

            cmd = ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", script_path, "-NoCleanup"]
            try:
                subprocess.run(cmd, check=True)
            finally:
                if original_settings:
                    with open(settings_path, 'w') as f: f.write(original_settings)
            
            # Rename the result to TemplateUltra.apk
            output_dir = os.path.join(os.path.dirname(self.core_dir), "FINISHED_HERE")
            src = os.path.join(output_dir, placeholder_filename)
            dst = os.path.join(output_dir, "TemplateUltra.apk")
            if os.path.exists(src):
                if os.path.exists(dst): os.remove(dst)
                os.rename(src, dst)
                
        else:
            script_path = os.path.join(self.core_dir, "linux_mac_build_apk.sh")
            os.chmod(script_path, 0o755)
            
            # We pass the placeholder as the name
            subprocess.run([
                script_path, 
                "--url", "TEMPLATE_URL", 
                "--name", self.PLACEHOLDER_NAME + ".apk", # This sets the App Name
                "--no-cleanup"
            ], check=True)
            
            # Rename result
            output_dir = os.path.join(os.path.dirname(self.core_dir), "FINISHED_HERE")
            src = os.path.join(output_dir, self.PLACEHOLDER_NAME + ".apk")
            dst = os.path.join(output_dir, "TemplateUltra.apk")
            if os.path.exists(src):
                if os.path.exists(dst): os.remove(dst)
                os.rename(src, dst)

    def build(self, url, app_name, job_id, progress_callback=None):
        if progress_callback: progress_callback(10)
        
        output_dir = os.path.join(os.path.dirname(self.core_dir), "FINISHED_HERE")
        template_apk = os.path.join(output_dir, "TemplateUltra.apk")
        
        # 1. Copy Template
        temp_apk = os.path.join(self.work_dir_base, f"temp_{job_id}.apk")
        shutil.copy2(template_apk, temp_apk)
        
        if progress_callback: progress_callback(30)
        
        # 2. Modify ZIP (Assets & Manifest)
        # We need to read the manifest, patch it, and write it back.
        # We also need to write the config.properties.
        
        # We can't easily modify a file inside a ZIP in-place with standard zipfile.
        # We have to copy to a new zip.
        
        unsigned_apk = os.path.join(self.work_dir_base, f"unsigned_{job_id}.apk")
        
        with zipfile.ZipFile(temp_apk, 'r') as zin:
            with zipfile.ZipFile(unsigned_apk, 'w') as zout:
                for item in zin.infolist():
                    buffer = zin.read(item.filename)
                    
                    if item.filename == "assets/config.properties":
                        # Replace config
                        buffer = f"url={url}".encode('utf-8')
                    
                    elif item.filename == "AndroidManifest.xml":
                        # Binary Patching
                        placeholder_bytes = self.PLACEHOLDER_NAME.encode('utf-16le')
                        app_name_bytes = app_name.encode('utf-16le')
                        
                        if placeholder_bytes in buffer:
                            # We found the placeholder!
                            # The structure in binary XML for a string is:
                            # [Length (2 bytes)] [String Bytes (UTF-16LE)] [Null Terminator (2 bytes)]
                            # But AXML is complex. Usually the string pool is at the beginning.
                            # We just overwrite the bytes.
                            
                            # Ensure new name fits
                            if len(app_name_bytes) > len(placeholder_bytes):
                                # Truncate if too long (shouldn't happen with 50 chars)
                                app_name_bytes = app_name_bytes[:len(placeholder_bytes)]
                            
                            # Pad with nulls if shorter
                            padding = len(placeholder_bytes) - len(app_name_bytes)
                            new_bytes = app_name_bytes + (b'\x00' * padding)
                            
                            # Replace
                            buffer = buffer.replace(placeholder_bytes, new_bytes)
                            
                            # Note: We are NOT updating the length prefix. 
                            # Android usually ignores the length prefix if null terminator is present, 
                            # OR it uses the length prefix from the String Pool header.
                            # Updating the length prefix in the String Pool is hard without parsing chunks.
                            # However, simply padding with nulls usually works because the renderer stops at null.
                        else:
                            print("Warning: Placeholder not found in Manifest!")
                            
                    zout.writestr(item, buffer)
        
        if progress_callback: progress_callback(60)
        
        # 3. Zipalign
        zipalign = self._get_build_tool("zipalign")
        aligned_apk = os.path.join(self.work_dir_base, f"aligned_{job_id}.apk")
        
        subprocess.run([zipalign, "-f", "4", unsigned_apk, aligned_apk], 
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                       
        if progress_callback: progress_callback(80)

        # 4. Sign
        apksigner = self._get_build_tool("apksigner")
        if not apksigner: apksigner = self._get_build_tool("apksigner.bat")
        
        final_apk_name = app_name if app_name.endswith(".apk") else f"{app_name}.apk"
        final_apk_path = os.path.join(output_dir, final_apk_name)
        
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
        
        # Cleanup
        if os.path.exists(temp_apk): os.remove(temp_apk)
        if os.path.exists(unsigned_apk): os.remove(unsigned_apk)
        if os.path.exists(aligned_apk): os.remove(aligned_apk)
        
        return final_apk_path
