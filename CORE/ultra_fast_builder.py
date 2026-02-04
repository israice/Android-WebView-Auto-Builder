import os, shutil, subprocess, zipfile

try: import fcntl; lock_file = lambda f: fcntl.flock(f, fcntl.LOCK_EX); unlock_file = lambda f: fcntl.flock(f, fcntl.LOCK_UN)
except ImportError: import msvcrt; lock_file = lambda f: msvcrt.locking(f.fileno(), msvcrt.LK_LOCK, 1); unlock_file = lambda f: msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)

class UltraFastBuilder:
    PLACEHOLDER_NAME = "PLACEHOLDER_APP_NAME__________________________"

    def __init__(self, core_dir):
        self.core_dir, self.is_windows = core_dir, os.name == 'nt'
        self.template_dir = os.path.join(core_dir, "apk_template_ultra")
        self.keystore_path = os.path.join(core_dir, "debug.keystore")
        self.work_dir_base = os.path.abspath(os.path.join(core_dir, "..", "android_build_env"))
        self.sdk_dir, self.jdk_dir = [os.path.join(self.work_dir_base, d) for d in ("sdk", "jdk")]

    def _get_build_tool(self, tool_name):
        build_tools_dir = os.path.join(self.sdk_dir, "build-tools")
        if not os.path.exists(build_tools_dir): return None
        if not (versions := sorted(os.listdir(build_tools_dir))): return None
        latest = versions[-1]
        if self.is_windows and not tool_name.endswith((".exe", ".bat")):
            for ext in (".exe", ".bat"):
                if os.path.exists(path := os.path.join(build_tools_dir, latest, tool_name + ext)): return path
        tool_path = os.path.join(build_tools_dir, latest, tool_name)
        return tool_path if os.path.exists(tool_path) else None

    def prepare_environment(self):
        lock_path = os.path.join(self.work_dir_base, ".init.lock")
        os.makedirs(self.work_dir_base, exist_ok=True)
        with open(lock_path, 'w') as f:
            lock_file(f)
            try:
                output_dir = os.path.join(os.path.dirname(self.core_dir), "FINISHED_HERE")
                if not os.path.exists(os.path.join(output_dir, "TemplateUltra.apk")) or not self._get_build_tool("zipalign"):
                    print("Generating Ultra Fast Template..."); self._create_template()
                self._ensure_keystore()
            finally: unlock_file(f)

    def _ensure_keystore(self):
        if os.path.exists(self.keystore_path): return
        print("Generating debug.keystore...")
        keytool = "keytool.exe" if self.is_windows else "keytool"
        possible_path = os.path.join(self.jdk_dir, "bin", keytool)
        keytool_path = possible_path if os.path.exists(possible_path) else keytool
        cmd = [keytool_path, "-genkey", "-v", "-keystore", self.keystore_path, "-storepass", "android",
               "-alias", "androiddebugkey", "-keypass", "android", "-keyalg", "RSA", "-keysize", "2048",
               "-validity", "10000", "-dname", "CN=Android Debug,O=Android,C=US"]
        try: subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE); print(f"Created keystore at {self.keystore_path}")
        except subprocess.CalledProcessError as e: print(f"Failed to generate keystore: {e.stderr.decode('utf-8', errors='ignore')}"); raise

    def _create_template(self):
        output_dir = os.path.join(os.path.dirname(self.core_dir), "FINISHED_HERE")
        placeholder_filename = self.PLACEHOLDER_NAME + ".apk"
        dst = os.path.join(output_dir, "TemplateUltra.apk")

        if self.is_windows:
            script_path = os.path.join(self.core_dir, "windows_build_apk.ps1")
            settings_path = os.path.join(self.core_dir, "..", "settings.yaml")
            original_settings = open(settings_path).read() if os.path.exists(settings_path) else None  # closed by GC
            with open(settings_path, 'w') as f: f.write(f'redirect_to_url: "TEMPLATE_URL"\napk_name: "{placeholder_filename}"')
            try: subprocess.run(["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", script_path, "-NoCleanup"], check=True)
            finally:
                if original_settings: open(settings_path, 'w').write(original_settings)
        else:
            script_path = os.path.join(self.core_dir, "linux_mac_build_apk.sh")
            os.chmod(script_path, 0o755)
            subprocess.run([script_path, "--url", "TEMPLATE_URL", "--name", placeholder_filename, "--no-cleanup"], check=True)

        src = os.path.join(output_dir, placeholder_filename)
        if os.path.exists(src):
            os.path.exists(dst) and os.remove(dst); os.rename(src, dst)

    def build(self, url, app_name, job_id, progress_callback=None):
        cb = progress_callback or (lambda x: None)
        cb(10)

        output_dir = os.path.join(os.path.dirname(self.core_dir), "FINISHED_HERE")
        template_apk = os.path.join(output_dir, "TemplateUltra.apk")
        temp_apk = os.path.join(self.work_dir_base, f"temp_{job_id}.apk")
        unsigned_apk = os.path.join(self.work_dir_base, f"unsigned_{job_id}.apk")
        aligned_apk = os.path.join(self.work_dir_base, f"aligned_{job_id}.apk")

        shutil.copy2(template_apk, temp_apk); cb(30)

        with zipfile.ZipFile(temp_apk, 'r') as zin, zipfile.ZipFile(unsigned_apk, 'w') as zout:
            for item in zin.infolist():
                buffer = zin.read(item.filename)
                if item.filename == "assets/config.properties":
                    buffer = f"url={url}".encode('utf-8')
                elif item.filename == "AndroidManifest.xml":
                    placeholder_bytes, app_name_bytes = self.PLACEHOLDER_NAME.encode('utf-16le'), app_name.encode('utf-16le')
                    if placeholder_bytes in buffer:
                        app_name_bytes = app_name_bytes[:len(placeholder_bytes)] if len(app_name_bytes) > len(placeholder_bytes) else app_name_bytes
                        new_bytes = app_name_bytes + (b'\x00' * (len(placeholder_bytes) - len(app_name_bytes)))
                        buffer = buffer.replace(placeholder_bytes, new_bytes)
                    else: print("Warning: Placeholder not found in Manifest!")
                zout.writestr(item, buffer)
        cb(60)

        subprocess.run([self._get_build_tool("zipalign"), "-f", "4", unsigned_apk, aligned_apk],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        cb(80)

        apksigner = self._get_build_tool("apksigner") or self._get_build_tool("apksigner.bat")
        final_apk_name = app_name if app_name.endswith(".apk") else f"{app_name}.apk"
        final_apk_path = os.path.join(output_dir, final_apk_name)

        env = os.environ.copy()
        if os.path.exists(jdk_bin := os.path.join(self.jdk_dir, "bin")):
            env["JAVA_HOME"], env["PATH"] = self.jdk_dir, jdk_bin + os.pathsep + env["PATH"]

        try:
            subprocess.run([apksigner, "sign", "--ks", self.keystore_path, "--ks-pass", "pass:android",
                           "--out", final_apk_path, aligned_apk], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        except subprocess.CalledProcessError as e:
            print(f"APKSigner Failed! Stderr: {e.stderr.decode('utf-8', errors='ignore')}"); raise
        cb(100)

        for f in (temp_apk, unsigned_apk, aligned_apk):
            os.path.exists(f) and os.remove(f)
        return final_apk_path
