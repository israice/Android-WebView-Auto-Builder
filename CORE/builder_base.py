"""Abstract base class for APK builders.

This module provides a common interface and shared functionality
for all APK builder implementations, reducing code duplication.

Classes:
    APKBuilderBase: Abstract base class with shared methods

Example:
    class MyBuilder(APKBuilderBase):
        def prepare_environment(self) -> None:
            # Implementation
            pass

        def build(self, url, app_name, job_id, progress_callback=None) -> str:
            # Implementation
            return "/path/to/app.apk"
"""

import os
import subprocess
import logging
from abc import ABC, abstractmethod
from typing import Optional, Callable, List

logger = logging.getLogger(__name__)


class APKBuilderBase(ABC):
    """Abstract base class for APK builders.

    Provides common functionality for keystore management,
    build tool discovery, APK alignment, and signing.

    Attributes:
        core_dir: Path to CORE directory containing build scripts
        is_windows: True if running on Windows
        work_dir_base: Base directory for temporary build files
        sdk_dir: Path to Android SDK
        jdk_dir: Path to JDK
        keystore_path: Path to signing keystore

    Example:
        class FastBuilder(APKBuilderBase):
            def prepare_environment(self) -> None:
                self.ensure_keystore()

            def build(self, url, app_name, job_id, progress_callback=None) -> str:
                # Build implementation
                return output_path
    """

    def __init__(self, core_dir: str) -> None:
        """Initialize builder with core directory.

        Args:
            core_dir: Path to CORE directory containing scripts and templates
        """
        self.core_dir: str = core_dir
        self.is_windows: bool = os.name == 'nt'
        self.work_dir_base: str = os.path.abspath(
            os.path.join(core_dir, "..", "android_build_env")
        )
        self.sdk_dir: str = os.path.join(self.work_dir_base, "sdk")
        self.jdk_dir: str = os.path.join(self.work_dir_base, "jdk")
        self.keystore_path: str = os.path.join(core_dir, "debug.keystore")

    def get_build_tool(self, tool_name: str) -> Optional[str]:
        """Find Android build tool in SDK.

        Searches the SDK build-tools directory for the specified tool,
        handling Windows extension (.exe, .bat) automatically.

        Args:
            tool_name: Name of tool (e.g., 'zipalign', 'apksigner')

        Returns:
            Full path to tool executable, or None if not found

        Example:
            zipalign = builder.get_build_tool("zipalign")
            if zipalign:
                subprocess.run([zipalign, "-f", "4", input_apk, output_apk])
        """
        build_tools_dir = os.path.join(self.sdk_dir, "build-tools")
        if not os.path.exists(build_tools_dir):
            return None

        versions = sorted(os.listdir(build_tools_dir))
        if not versions:
            return None

        latest = versions[-1]

        # On Windows, try with .exe and .bat extensions
        if self.is_windows and not tool_name.endswith((".exe", ".bat")):
            for ext in (".exe", ".bat"):
                path = os.path.join(build_tools_dir, latest, tool_name + ext)
                if os.path.exists(path):
                    return path

        tool_path = os.path.join(build_tools_dir, latest, tool_name)
        return tool_path if os.path.exists(tool_path) else None

    def ensure_keystore(self) -> None:
        """Generate debug keystore if it doesn't exist.

        Creates a new debug keystore using keytool with credentials
        from environment variables (KEYSTORE_PASSWORD, KEYSTORE_ALIAS).

        Raises:
            subprocess.CalledProcessError: If keytool fails
        """
        if os.path.exists(self.keystore_path):
            return

        logger.info("Generating debug.keystore...")
        keytool = "keytool.exe" if self.is_windows else "keytool"
        possible_path = os.path.join(self.jdk_dir, "bin", keytool)
        keytool_path = possible_path if os.path.exists(possible_path) else keytool

        ks_pass = os.environ.get('KEYSTORE_PASSWORD', 'android')
        ks_alias = os.environ.get('KEYSTORE_ALIAS', 'androiddebugkey')

        cmd: List[str] = [
            keytool_path, "-genkey", "-v",
            "-keystore", self.keystore_path,
            "-storepass", ks_pass,
            "-alias", ks_alias,
            "-keypass", ks_pass,
            "-keyalg", "RSA",
            "-keysize", "2048",
            "-validity", "10000",
            "-dname", "CN=Android Debug,O=Android,C=US"
        ]

        try:
            subprocess.run(cmd, check=True, capture_output=True)
            logger.info(f"Created keystore at {self.keystore_path}")
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to generate keystore: {e.stderr.decode('utf-8', errors='ignore')}")
            raise

    def align_apk(self, input_apk: str, output_apk: str) -> None:
        """Align APK for optimization.

        Uses zipalign to optimize the APK's resource alignment
        for faster loading on Android devices.

        Args:
            input_apk: Path to unaligned APK
            output_apk: Path for aligned output APK

        Raises:
            FileNotFoundError: If zipalign not found in SDK
            subprocess.CalledProcessError: If zipalign fails
        """
        zipalign = self.get_build_tool("zipalign")
        if not zipalign:
            raise FileNotFoundError("zipalign not found in SDK")

        subprocess.run(
            [zipalign, "-f", "4", input_apk, output_apk],
            check=True, capture_output=True
        )

    def get_apksigner(self) -> Optional[str]:
        """Get path to apksigner tool with platform-specific fallback.

        Returns:
            Path to apksigner executable, or None if not found
        """
        return self.get_build_tool("apksigner") or self.get_build_tool("apksigner.bat")

    def sign_apk(self, input_apk: str, output_apk: str) -> None:
        """Sign APK with keystore.

        Uses apksigner to sign the APK with the debug keystore.
        Credentials are read from environment variables.

        Args:
            input_apk: Path to aligned but unsigned APK
            output_apk: Path for signed output APK

        Raises:
            FileNotFoundError: If apksigner not found in SDK
            subprocess.CalledProcessError: If signing fails
        """
        apksigner = self.get_apksigner()
        if not apksigner:
            raise FileNotFoundError("apksigner not found in SDK")

        ks_pass = os.environ.get('KEYSTORE_PASSWORD', 'android')

        env = os.environ.copy()
        jdk_bin = os.path.join(self.jdk_dir, "bin")
        if os.path.exists(jdk_bin):
            env["JAVA_HOME"] = self.jdk_dir
            env["PATH"] = jdk_bin + os.pathsep + env["PATH"]

        try:
            # Pass password via stdin to avoid exposure in process list (ps aux)
            subprocess.run(
                [apksigner, "sign", "--ks", self.keystore_path,
                 "--ks-pass", "stdin", "--out", output_apk, input_apk],
                input=f"{ks_pass}\n".encode(),
                check=True, capture_output=True, env=env
            )
        except subprocess.CalledProcessError as e:
            logger.error(f"APKSigner failed: {e.stderr.decode('utf-8', errors='ignore')}")
            raise

    @abstractmethod
    def prepare_environment(self) -> None:
        """Prepare build environment.

        Must be implemented by subclasses to set up any required
        resources like SDK, templates, keystores, etc.
        """
        pass

    @abstractmethod
    def build(
        self,
        url: str,
        app_name: str,
        job_id: str,
        progress_callback: Optional[Callable[[int], None]] = None
    ) -> str:
        """Build APK from URL.

        Must be implemented by subclasses to perform the actual
        APK generation.

        Args:
            url: Website URL to embed in APK
            app_name: Display name for the Android app
            job_id: Unique identifier for this build job
            progress_callback: Optional callback for progress updates (0-100)

        Returns:
            Absolute path to the generated APK file
        """
        pass
