import os, shutil, subprocess, requests, tempfile
from xml.etree import ElementTree as ET

class FastApkBuilder:
    def __init__(self, core_dir):
        self.core_dir = core_dir
        self.apktool_jar = os.path.join(core_dir, "apktool.jar")
        self.template_dir = os.path.join(core_dir, "apk_template")
        self.keystore_path = os.path.join(core_dir, "debug.keystore")
        self.is_windows = os.name == 'nt'
        self.work_dir_base = os.path.abspath(os.path.join(core_dir, "..", "android_build_env")) if self.is_windows else os.path.join(tempfile.gettempdir(), "android_build_env")
        self.sdk_dir = os.path.join(self.work_dir_base, "sdk")
        self.jdk_dir = os.path.join(self.work_dir_base, "jdk")

    def _get_java_cmd(self):
        java_bin = os.path.join(self.jdk_dir, "bin", "java.exe" if self.is_windows else "java")
        return java_bin if os.path.exists(java_bin) else "java"

    def _get_build_tool(self, tool_name):
        build_tools_dir = os.path.join(self.sdk_dir, "build-tools")
        if not os.path.exists(build_tools_dir): return None
        if not (versions := sorted(os.listdir(build_tools_dir))): return None
        latest = versions[-1]
        if self.is_windows and not tool_name.endswith((".exe", ".bat")):
            for ext in [".exe", ".bat"]:
                if os.path.exists(path := os.path.join(build_tools_dir, latest, tool_name + ext)): return path
        tool_path = os.path.join(build_tools_dir, latest, tool_name)
        return tool_path if os.path.exists(tool_path) else None

    def prepare_environment(self):
        if not os.path.exists(self.apktool_jar):
            print("Downloading apktool.jar...")
            response = requests.get("https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.9.1.jar", allow_redirects=True)
            with open(self.apktool_jar, 'wb') as f: f.write(response.content)
        if not os.path.exists(self.template_dir) or not self._get_build_tool("zipalign"):
            print("Generating APK Template (and restoring SDK)...")
            self._create_template()
        if not os.path.exists(self.keystore_path):
            print("Generating debug keystore...")
            keytool = os.path.join(self.jdk_dir, "bin", "keytool.exe" if self.is_windows else "keytool")
            keytool = keytool if os.path.exists(keytool) else "keytool"
            try:
                subprocess.run([keytool, "-genkey", "-v", "-keystore", self.keystore_path,
                    "-storepass", "android", "-alias", "androiddebugkey", "-keypass", "android",
                    "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000",
                    "-dname", "CN=Android Debug,O=Android,C=US"], check=False, shell=self.is_windows)
            except Exception as e: print(f"Warning: Failed to generate keystore: {e}")

    def _create_template(self):
        settings_path = os.path.join(self.core_dir, "..", "settings.yaml")
        if self.is_windows:
            script_path = os.path.join(self.core_dir, "windows_build_apk.ps1")
            cmd = ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", script_path, "-NoCleanup"]
            original_settings = open(settings_path, 'r').read() if os.path.exists(settings_path) else None
            with open(settings_path, 'w') as f: f.write('redirect_to_url: "TEMPLATE_URL"\napk_name: "Template.apk"')
            try: subprocess.run(cmd, check=True)
            finally:
                if original_settings:
                    with open(settings_path, 'w') as f: f.write(original_settings)
        else:
            script_path = os.path.join(self.core_dir, "linux_mac_build_apk.sh")
            os.chmod(script_path, 0o755)
            subprocess.run([script_path, "--url", "TEMPLATE_URL", "--name", "Template.apk", "--no-cleanup"], check=True)
        output_dir = os.path.join(os.path.dirname(self.core_dir), "FINISHED_HERE")
        apk_path = os.path.join(output_dir, "Template.apk")
        if not os.path.exists(apk_path): raise Exception("Template build failed: APK not found")
        print("Decompiling template...")
        subprocess.run([self._get_java_cmd(), "-jar", self.apktool_jar, "d", "-f", "-o", self.template_dir, apk_path], check=True)
        print("Template created successfully.")

    def build(self, url, app_name, job_id, progress_callback=None):
        progress_callback and progress_callback(10)
        job_dir = os.path.join(self.work_dir_base, f"job_{job_id}")
        os.path.exists(job_dir) and shutil.rmtree(job_dir)
        shutil.copytree(self.template_dir, job_dir)
        progress_callback and progress_callback(30)
        try:
            config_path = os.path.join(job_dir, "assets", "config.properties")
            os.makedirs(os.path.dirname(config_path), exist_ok=True)
            with open(config_path, "w") as f: f.write(f"url={url}")
            strings_path = self._find_strings_xml(job_dir)
            if strings_path:
                tree = ET.parse(strings_path)
                if el := next((s for s in tree.getroot().findall('string') if s.get('name') == 'app_name'), None):
                    el.text = app_name
                tree.write(strings_path, encoding='utf-8', xml_declaration=True)
            progress_callback and progress_callback(50)
            unsigned_apk = os.path.join(self.work_dir_base, f"unsigned_{job_id}.apk")
            subprocess.run([self._get_java_cmd(), "-jar", self.apktool_jar, "b", job_dir, "-o", unsigned_apk],
                check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            progress_callback and progress_callback(70)
            if not (zipalign := self._get_build_tool("zipalign")): raise Exception("zipalign not found in SDK")
            aligned_apk = os.path.join(self.work_dir_base, f"aligned_{job_id}.apk")
            subprocess.run([zipalign, "-f", "-v", "4", unsigned_apk, aligned_apk],
                check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            progress_callback and progress_callback(80)
            apksigner = self._get_build_tool("apksigner") or self._get_build_tool("apksigner.bat")
            if not apksigner: raise Exception("apksigner not found in SDK")
            final_apk_name = app_name if app_name.endswith(".apk") else f"{app_name}.apk"
            output_dir = os.path.join(os.path.dirname(self.core_dir), "FINISHED_HERE")
            final_apk_path = os.path.join(output_dir, final_apk_name)
            env = os.environ.copy()
            if os.path.exists(os.path.join(self.jdk_dir, "bin")):
                env["JAVA_HOME"] = self.jdk_dir
                env["PATH"] = os.path.join(self.jdk_dir, "bin") + os.pathsep + env["PATH"]
            subprocess.run([apksigner, "sign", "--ks", self.keystore_path, "--ks-pass", "pass:android",
                "--out", final_apk_path, aligned_apk], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
            progress_callback and progress_callback(100)
            return final_apk_path
        finally:
            for p in [job_dir, os.path.join(self.work_dir_base, f"unsigned_{job_id}.apk"),
                      os.path.join(self.work_dir_base, f"aligned_{job_id}.apk")]:
                shutil.rmtree(p) if os.path.isdir(p) else (os.remove(p) if os.path.exists(p) else None)

    def _find_strings_xml(self, job_dir):
        for root, _, files in os.walk(os.path.join(job_dir, "res")):
            if "strings.xml" in files:
                path = os.path.join(root, "strings.xml")
                with open(path, 'r', encoding='utf-8') as f:
                    if 'name="app_name"' in f.read(): return path
        return None
