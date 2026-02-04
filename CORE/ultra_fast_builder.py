"""Ultra-fast APK builder using binary template patching.

This module provides the UltraFastBuilder class which creates APKs
by modifying a pre-built template, avoiding full recompilation.
Build times are typically under 1 second.

Example:
    builder = UltraFastBuilder('/path/to/CORE')
    builder.prepare_environment()
    apk_path = builder.build('https://example.com', 'MyApp', 'job-123')
"""

import os
import shutil
import subprocess
import zipfile
import logging
import hashlib
from typing import Optional, Callable

from CORE.builder_base import APKBuilderBase

# Platform-specific file locking
try:
    import fcntl

    def lock_file(f) -> None:
        fcntl.flock(f, fcntl.LOCK_EX)

    def unlock_file(f) -> None:
        fcntl.flock(f, fcntl.LOCK_UN)
except ImportError:
    import msvcrt
    import time

    def lock_file(f) -> None:
        # Write a byte to ensure file is not empty (msvcrt.locking requires content)
        f.write(' ')
        f.flush()
        f.seek(0)
        # Use non-blocking lock with retry to avoid deadlock
        for _ in range(10):
            try:
                msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
                return
            except OSError:
                time.sleep(0.1)
        # If retries exhausted, try blocking lock as last resort
        msvcrt.locking(f.fileno(), msvcrt.LK_LOCK, 1)

    def unlock_file(f) -> None:
        try:
            f.seek(0)
            msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)
        except OSError:
            pass  # Already unlocked or never locked

logger = logging.getLogger(__name__)


class UltraFastBuilder(APKBuilderBase):
    """Ultra-fast APK builder using binary template patching.

    This builder creates APKs by modifying a pre-built template APK,
    replacing the app name and URL configuration without recompilation.
    Build time is typically under 1 second.

    The process:
    1. Copy template APK to temp location
    2. Modify assets/config.properties with target URL
    3. Patch AndroidManifest.xml with app name (UTF-16LE)
    4. Align APK with zipalign
    5. Sign APK with apksigner

    Attributes:
        PLACEHOLDER_NAME: Placeholder string in template for app name
        template_dir: Path to APK template directory

    Example:
        builder = UltraFastBuilder('/path/to/CORE')
        builder.prepare_environment()

        def on_progress(percent):
            print(f"Build {percent}% complete")

        apk_path = builder.build(
            url='https://mysite.com',
            app_name='My App',
            job_id='abc-123',
            progress_callback=on_progress
        )
    """

    PLACEHOLDER_NAME: str = "PLACEHOLDER_APP_NAME__________________________"
    PLACEHOLDER_APPID: str = "app00000000"  # 8 zeros for unique hex suffix

    def __init__(self, core_dir: str) -> None:
        """Initialize the ultra-fast builder.

        Args:
            core_dir: Path to CORE directory containing build scripts
        """
        super().__init__(core_dir)
        self.template_dir: str = os.path.join(core_dir, "apk_template_ultra")

    def prepare_environment(self) -> None:
        """Prepare the build environment with template and keystore.

        Creates the template APK if it doesn't exist and ensures
        the debug keystore is available.
        """
        os.makedirs(self.work_dir_base, exist_ok=True)

        output_dir = os.path.join(os.path.dirname(self.core_dir), "FINISHED_HERE")
        template_exists = os.path.exists(os.path.join(output_dir, "TemplateUltra.apk"))
        tools_exist = self.get_build_tool("zipalign") is not None

        if not template_exists or not tools_exist:
            logger.info("Generating Ultra Fast Template...")
            self._create_template()

        self.ensure_keystore()

    def _create_template(self) -> None:
        """Create the template APK with placeholder app name.

        Runs the platform-specific build script to create a template
        APK that can be patched for each build.
        """
        output_dir = os.path.join(os.path.dirname(self.core_dir), "FINISHED_HERE")
        placeholder_filename = self.PLACEHOLDER_NAME + ".apk"
        dst = os.path.join(output_dir, "TemplateUltra.apk")

        if self.is_windows:
            script_path = os.path.join(self.core_dir, "windows_build_apk.ps1")
            settings_path = os.path.join(self.core_dir, "..", "settings.yaml")

            # Read original settings with proper file handling
            original_settings: Optional[str] = None
            if os.path.exists(settings_path):
                with open(settings_path, 'r', encoding='utf-8') as sf:
                    original_settings = sf.read()

            # Write temporary settings
            with open(settings_path, 'w', encoding='utf-8') as sf:
                sf.write(f'redirect_to_url: "TEMPLATE_URL"\napk_name: "{placeholder_filename}"')

            try:
                # Don't capture output so user can see progress
                subprocess.run(
                    ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", script_path, "-NoCleanup"],
                    check=True
                )
            finally:
                # Restore original settings
                if original_settings:
                    with open(settings_path, 'w', encoding='utf-8') as sf:
                        sf.write(original_settings)
        else:
            script_path = os.path.join(self.core_dir, "linux_mac_build_apk.sh")
            os.chmod(script_path, 0o755)
            # Don't capture output so user can see progress
            subprocess.run(
                [script_path, "--url", "TEMPLATE_URL", "--name", placeholder_filename, "--no-cleanup"],
                check=True
            )

        # Rename to template
        src = os.path.join(output_dir, placeholder_filename)
        if os.path.exists(src):
            if os.path.exists(dst):
                os.remove(dst)
            os.rename(src, dst)
            logger.info(f"Template created at {dst}")

    def _generate_unique_appid(self, url: str, job_id: str) -> str:
        """Generate unique applicationId suffix from URL and job_id.

        Creates an 8-character hex string derived from hashing the URL
        and job_id. This ensures each APK gets a unique package name,
        allowing multiple apps to be installed side-by-side.

        Args:
            url: The target URL for this APK
            job_id: Unique job identifier

        Returns:
            String like 'appa1b2c3d4' (11 chars total)
        """
        unique_string = f"{url}:{job_id}"
        hash_bytes = hashlib.md5(unique_string.encode()).hexdigest()[:8]
        return f"app{hash_bytes}"

    def build(
        self,
        url: str,
        app_name: str,
        job_id: str,
        progress_callback: Optional[Callable[[int], None]] = None
    ) -> str:
        """Build a customized APK from template.

        Creates a new APK by copying the template and replacing:
        - assets/config.properties: URL configuration
        - AndroidManifest.xml: Application name (UTF-16LE encoded)

        Args:
            url: The website URL to load in WebView
            app_name: Display name for the Android application (max 48 chars)
            job_id: Unique identifier for this build job
            progress_callback: Optional callback receiving progress percentage (0-100)

        Returns:
            Absolute path to the signed and aligned APK file

        Raises:
            FileNotFoundError: If template APK or build tools not found
            subprocess.CalledProcessError: If zipalign or apksigner fails
        """
        cb = progress_callback or (lambda x: None)
        cb(10)

        output_dir = os.path.join(os.path.dirname(self.core_dir), "FINISHED_HERE")
        template_apk = os.path.join(output_dir, "TemplateUltra.apk")
        temp_apk = os.path.join(self.work_dir_base, f"temp_{job_id}.apk")
        unsigned_apk = os.path.join(self.work_dir_base, f"unsigned_{job_id}.apk")
        aligned_apk = os.path.join(self.work_dir_base, f"aligned_{job_id}.apk")

        # Generate unique applicationId suffix
        unique_appid = self._generate_unique_appid(url, job_id)
        logger.info(f"Generated unique applicationId suffix: {unique_appid}")

        # Copy template
        shutil.copy2(template_apk, temp_apk)
        cb(30)

        # Patch APK contents
        with zipfile.ZipFile(temp_apk, 'r') as zin, zipfile.ZipFile(unsigned_apk, 'w') as zout:
            for item in zin.infolist():
                buffer = zin.read(item.filename)

                if item.filename == "assets/config.properties":
                    # Replace URL configuration
                    buffer = f"url={url}".encode('utf-8')

                elif item.filename == "AndroidManifest.xml":
                    # Replace app name in manifest (UTF-16LE encoded)
                    placeholder_bytes = self.PLACEHOLDER_NAME.encode('utf-16le')
                    app_name_bytes = app_name.encode('utf-16le')

                    if placeholder_bytes in buffer:
                        # Truncate or pad app name to match placeholder length
                        if len(app_name_bytes) > len(placeholder_bytes):
                            app_name_bytes = app_name_bytes[:len(placeholder_bytes)]
                        new_bytes = app_name_bytes + (b'\x00' * (len(placeholder_bytes) - len(app_name_bytes)))
                        buffer = buffer.replace(placeholder_bytes, new_bytes)
                    else:
                        logger.warning("App name placeholder not found in Manifest!")

                    # Replace applicationId placeholder (UTF-16LE encoded)
                    appid_placeholder_bytes = self.PLACEHOLDER_APPID.encode('utf-16le')
                    unique_appid_bytes = unique_appid.encode('utf-16le')

                    if appid_placeholder_bytes in buffer:
                        buffer = buffer.replace(appid_placeholder_bytes, unique_appid_bytes)
                        logger.info(f"Patched applicationId: {self.PLACEHOLDER_APPID} -> {unique_appid}")
                    else:
                        logger.warning("ApplicationId placeholder not found in Manifest!")

                zout.writestr(item, buffer)
        cb(60)

        # Align APK
        zipalign = self.get_build_tool("zipalign")
        if not zipalign:
            raise FileNotFoundError("zipalign not found in SDK")

        subprocess.run(
            [zipalign, "-f", "4", unsigned_apk, aligned_apk],
            check=True, capture_output=True
        )
        cb(80)

        # Sign APK (uses inherited method from APKBuilderBase)
        final_apk_name = app_name if app_name.endswith(".apk") else f"{app_name}.apk"
        final_apk_path = os.path.join(output_dir, final_apk_name)
        self.sign_apk(aligned_apk, final_apk_path)

        cb(100)

        # Cleanup temporary files
        for temp_file in (temp_apk, unsigned_apk, aligned_apk):
            if os.path.exists(temp_file):
                os.remove(temp_file)

        return final_apk_path
