"""Security utilities module for Android-WebView-Auto-Builder.

This module provides security-related utilities including:
- Thread-safe job storage with cleanup
- Rate limiting for API endpoints
- Input validation and sanitization
- Path traversal protection
- Security headers for HTTP responses

Example:
    from security import ThreadSafeJobs, sanitize_app_name, validate_url

    jobs = ThreadSafeJobs()
    jobs['abc-123'] = {'status': 'running'}

    safe_name = sanitize_app_name(user_input)
    safe_url = validate_url(user_url)
"""

import re
import os
import time
import threading
from typing import Dict, List, Optional, Any
from urllib.parse import urlparse


class ThreadSafeJobs:
    """Thread-safe dictionary for job storage with automatic cleanup.

    Provides a dictionary-like interface with thread-safe access
    for storing and retrieving job information.

    Attributes:
        _jobs: Internal dictionary storing job data
        _lock: RLock for thread synchronization

    Example:
        jobs = ThreadSafeJobs()
        jobs['job-123'] = {'status': 'pending', 'start_time': time.time()}
        status = jobs.get('job-123', {}).get('status')
    """

    def __init__(self) -> None:
        """Initialize empty thread-safe job storage."""
        self._jobs: Dict[str, Dict[str, Any]] = {}
        self._lock: threading.RLock = threading.RLock()

    def __getitem__(self, key: str) -> Dict[str, Any]:
        """Get job by ID with thread safety."""
        with self._lock:
            return self._jobs[key]

    def __setitem__(self, key: str, value: Dict[str, Any]) -> None:
        """Set job data with thread safety."""
        with self._lock:
            self._jobs[key] = value

    def get(self, key: str, default: Optional[Dict[str, Any]] = None) -> Optional[Dict[str, Any]]:
        """Get job by ID, returning default if not found."""
        with self._lock:
            return self._jobs.get(key, default)

    def __contains__(self, key: str) -> bool:
        """Check if job ID exists."""
        with self._lock:
            return key in self._jobs

    def cleanup_old_jobs(self, max_age_seconds: int = 86400) -> int:
        """Remove jobs older than max_age_seconds.

        Args:
            max_age_seconds: Maximum job age in seconds (default: 24 hours)

        Returns:
            Number of jobs removed
        """
        cutoff = time.time() - max_age_seconds
        removed = 0
        with self._lock:
            for job_id in list(self._jobs.keys()):
                job = self._jobs.get(job_id, {})
                if job.get('start_time', 0) < cutoff:
                    del self._jobs[job_id]
                    removed += 1
        return removed


class RateLimiter:
    """Simple in-memory rate limiter for API protection.

    Tracks request timestamps per key (typically IP address) and
    enforces a maximum request rate within a sliding time window.

    Attributes:
        max_requests: Maximum requests allowed per window
        window_seconds: Duration of the sliding window

    Example:
        limiter = RateLimiter(max_requests=10, window_seconds=60)
        if not limiter.is_allowed(client_ip):
            return "Rate limit exceeded", 429
    """

    def __init__(self, max_requests: int = 10, window_seconds: int = 60) -> None:
        """Initialize rate limiter.

        Args:
            max_requests: Max requests per window (default: 10)
            window_seconds: Window duration in seconds (default: 60)
        """
        self._requests: Dict[str, List[float]] = {}
        self._lock: threading.Lock = threading.Lock()
        self.max_requests: int = max_requests
        self.window_seconds: int = window_seconds

    def is_allowed(self, key: str) -> bool:
        """Check if request is allowed for given key.

        Args:
            key: Identifier for rate limiting (e.g., IP address)

        Returns:
            True if request is allowed, False if rate limited
        """
        now = time.time()
        with self._lock:
            if key not in self._requests:
                self._requests[key] = []

            # Clean old entries
            self._requests[key] = [
                t for t in self._requests[key]
                if now - t < self.window_seconds
            ]

            if len(self._requests[key]) >= self.max_requests:
                return False

            self._requests[key].append(now)
            return True

    def cleanup_expired(self) -> int:
        """Remove expired rate limit entries.

        Cleans up entries for IPs that haven't made requests
        within the rate limit window.

        Returns:
            Number of entries removed
        """
        now = time.time()
        removed = 0
        with self._lock:
            for key in list(self._requests.keys()):
                self._requests[key] = [
                    t for t in self._requests[key]
                    if now - t < self.window_seconds
                ]
                if not self._requests[key]:
                    del self._requests[key]
                    removed += 1
        return removed


# Trusted proxy IP addresses for X-Forwarded-For validation
TRUSTED_PROXIES: set = {'127.0.0.1', '::1', '172.17.0.1'}


def get_client_ip(request) -> str:
    """Extract client IP address.

    Uses remote_addr directly. X-Forwarded-For is NOT trusted
    since server has direct access (no reverse proxy).
    This prevents rate limit bypass via header spoofing.

    Args:
        request: Flask request object

    Returns:
        Client IP address string
    """
    return request.remote_addr or '127.0.0.1'


def sanitize_app_name(name: str) -> str:
    """Sanitize app name to prevent command injection.

    Removes potentially dangerous characters and limits length
    to prevent shell injection and buffer overflow attacks.

    Args:
        name: Raw app name from user input

    Returns:
        Sanitized app name (max 50 characters)

    Raises:
        ValueError: If name is empty or invalid after sanitization

    Example:
        safe_name = sanitize_app_name("My App <script>")
        # Returns: "My App script"
    """
    if not name:
        raise ValueError("App name is required")

    # Convert to string and strip whitespace
    name = str(name).strip()

    # Allow only alphanumeric, spaces, hyphens, underscores, and some unicode letters
    # This regex removes any characters that could be dangerous in shell contexts
    sanitized = re.sub(r'[^\w\s\-]', '', name, flags=re.UNICODE)

    # Collapse multiple spaces
    sanitized = re.sub(r'\s+', ' ', sanitized).strip()

    # Limit length to 50 characters
    sanitized = sanitized[:50]

    if not sanitized:
        raise ValueError("Invalid app name - must contain alphanumeric characters")

    return sanitized


def validate_url(url: str) -> str:
    """Validate URL format and block dangerous URLs.

    Ensures URL uses HTTPS protocol only and is not pointing
    to internal/private network addresses. HTTP is blocked for security.

    Args:
        url: Raw URL from user input

    Returns:
        Validated URL string

    Raises:
        ValueError: If URL is invalid or potentially dangerous

    Example:
        safe_url = validate_url("https://example.com/page")
        safe_url = validate_url("example.com")  # Auto-prefixes to https://example.com
        validate_url("http://example.com")  # Raises ValueError (HTTP not allowed)
        validate_url("http://localhost")  # Raises ValueError
    """
    if not url:
        raise ValueError("URL is required")

    url = str(url).strip()

    # Auto-prefix https:// if no protocol specified (allows "example.com" input)
    if '://' not in url:
        url = 'https://' + url

    # Parse URL
    try:
        parsed = urlparse(url)
    except Exception:
        raise ValueError("Invalid URL format")

    # Block HTTP explicitly (only HTTPS allowed)
    if parsed.scheme == 'http':
        raise ValueError("HTTP is not allowed for security reasons. Use HTTPS instead.")

    # Check scheme - only HTTPS allowed for security
    if parsed.scheme != 'https':
        raise ValueError("URL must use HTTPS protocol")

    # Check for valid netloc (domain)
    if not parsed.netloc:
        raise ValueError("Invalid URL - missing domain")

    # Block internal/private addresses
    blocked_hosts = [
        'localhost',
        '127.0.0.1',
        '0.0.0.0',
        '::1',
        '10.',
        '172.16.', '172.17.', '172.18.', '172.19.',
        '172.20.', '172.21.', '172.22.', '172.23.',
        '172.24.', '172.25.', '172.26.', '172.27.',
        '172.28.', '172.29.', '172.30.', '172.31.',
        '192.168.',
        '169.254.',
    ]

    netloc_lower = parsed.netloc.lower()
    for blocked in blocked_hosts:
        if netloc_lower == blocked or netloc_lower.startswith(blocked):
            raise ValueError("Internal/private URLs are not allowed")

    # Block file:// and other dangerous schemes that might slip through
    if '://' in url and not url.lower().startswith('https://'):
        raise ValueError("Only HTTPS URLs are allowed")

    return url


def secure_filename(filename: str) -> str:
    """Sanitize filename to prevent path traversal attacks.

    Removes directory separators, null bytes, and '..' sequences
    to prevent unauthorized file access.

    Args:
        filename: Raw filename from user input

    Returns:
        Safe filename with only alphanumeric, underscore, hyphen, dot

    Raises:
        ValueError: If filename is invalid or potentially dangerous

    Example:
        safe = secure_filename("../../etc/passwd")  # Raises ValueError
        safe = secure_filename("my_app.apk")  # Returns: "my_app.apk"
    """
    if not filename:
        raise ValueError("Filename is required")

    filename = str(filename)

    # Remove null bytes
    filename = filename.replace('\x00', '')

    # Remove path separators
    filename = filename.replace('/', '').replace('\\', '')

    # Remove .. sequences
    while '..' in filename:
        filename = filename.replace('..', '')

    # Allow only safe characters: alphanumeric, underscore, hyphen, dot
    filename = re.sub(r'[^a-zA-Z0-9_\-.]', '', filename)

    # Don't allow hidden files (starting with .)
    if not filename or filename.startswith('.'):
        raise ValueError("Invalid filename")

    # Must have some content before extension
    if filename.startswith('.') or not filename.replace('.', ''):
        raise ValueError("Invalid filename")

    return filename


def validate_file_path(filepath: str, allowed_dir: str) -> str:
    """Validate that a file path is within an allowed directory.

    Resolves symlinks and ensures the final path is contained
    within the specified directory to prevent path traversal.

    Args:
        filepath: The file path to validate
        allowed_dir: The directory the file must be within

    Returns:
        The validated real (absolute) path

    Raises:
        ValueError: If path resolves to location outside allowed_dir

    Example:
        path = validate_file_path("/app/files/doc.pdf", "/app/files")
        validate_file_path("/etc/passwd", "/app/files")  # Raises ValueError
    """
    # Resolve to real paths (handles symlinks)
    real_path = os.path.realpath(filepath)
    real_allowed = os.path.realpath(allowed_dir)

    # Ensure the path is within the allowed directory
    # We add os.sep to prevent matching partial directory names
    if not (real_path.startswith(real_allowed + os.sep) or real_path == real_allowed):
        raise ValueError("Access denied - path outside allowed directory")

    return real_path


# Security headers configuration
SECURITY_HEADERS = {
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'X-XSS-Protection': '1; mode=block',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'Permissions-Policy': 'geolocation=(), microphone=(), camera=()',
    'Content-Security-Policy': (
        "default-src 'self'; "
        "script-src 'self' https://cdnjs.cloudflare.com https://cdn.jsdelivr.net; "
        "style-src 'self' 'unsafe-inline' https://cdnjs.cloudflare.com https://fonts.googleapis.com; "
        "font-src 'self' https://cdnjs.cloudflare.com https://fonts.gstatic.com; "
        "img-src 'self' data:; "
        "connect-src 'self'"
    ),
}


def add_security_headers(response: Any) -> Any:
    """Add security headers to a Flask response.

    Adds standard security headers including CSP, X-Frame-Options,
    and removes potentially revealing server headers.

    Args:
        response: Flask Response object

    Returns:
        Modified response with security headers added

    Example:
        @app.after_request
        def after_request(response):
            return add_security_headers(response)
    """
    for header, value in SECURITY_HEADERS.items():
        response.headers[header] = value

    # Remove potentially revealing headers
    response.headers.pop('Server', None)

    return response
