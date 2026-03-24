"""FastAPI web server for Android-WebView-Auto-Builder.

This module provides the REST API for creating Android APKs from URLs.
It handles job management, build orchestration, and file delivery.

Endpoints:
    GET /: Web dashboard
    POST /create: Create new APK build job
    GET /status/{job_id}: Check job status
    GET /download/{job_id}/{filename}: Download completed APK
    POST /webhook: GitHub webhook for auto-update
"""

import hashlib
import hmac
import os
import signal

from dotenv import load_dotenv
load_dotenv()
import subprocess
import sys
import threading
import time
import uuid
from typing import Optional, Dict, Any

from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse, FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.middleware.base import BaseHTTPMiddleware

from BACKEND.logging_config import setup_logging, get_logger
from BACKEND.security import (
    ThreadSafeJobs,
    RateLimiter,
    sanitize_app_name,
    validate_url,
    secure_filename,
    validate_file_path,
    SECURITY_HEADERS,
    get_client_ip,
)

# Initialize logging
setup_logging()
logger = get_logger(__name__)


def validate_environment() -> None:
    """Validate all required environment variables at startup.

    Raises:
        SystemExit: If any required variable is missing or invalid.
    """
    errors = []

    # Required for webhook auto-update
    if not os.environ.get("WEBHOOK_SECRET"):
        errors.append("WEBHOOK_SECRET is not set")

    # Required for APK signing
    if not os.environ.get("KEYSTORE_PASSWORD"):
        errors.append("KEYSTORE_PASSWORD is not set")

    if not os.environ.get("KEYSTORE_ALIAS"):
        errors.append("KEYSTORE_ALIAS is not set")

    if errors:
        for err in errors:
            logger.error(f"Configuration error: {err}")
        logger.error("Set required environment variables in .env file. See .env.example")
        sys.exit(1)


# Validate environment before anything else
validate_environment()

app = FastAPI()

# Mount static files and templates
app.mount("/static", StaticFiles(directory="FRONTEND"), name="static")
templates = Jinja2Templates(directory="FRONTEND")

# Configuration
CORE_DIR = os.path.join(os.getcwd(), 'BACKEND')
OUTPUT_DIR = os.path.join(os.getcwd(), 'DATA')
BUILD_SCRIPT = os.path.join(CORE_DIR, 'linux_mac_build_apk.sh')

# Webhook configuration for auto-update (already validated)
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "")

# Thread-safe job storage
jobs = ThreadSafeJobs()

# Rate limiter: 10 requests per minute per IP
# NOTE: In-memory rate limiting works only with single uvicorn worker.
# docker-compose.yml uses --workers 1 intentionally.
rate_limiter = RateLimiter(max_requests=10, window_seconds=60)

# Sync version badge on module load
try:
    subprocess.run(["python3", "TOOLS/sync_version.py"], capture_output=True, timeout=10)
except Exception as e:
    logger.debug(f"Version sync with python3 failed: {e}")
    try:
        subprocess.run(["python", "TOOLS/sync_version.py"], capture_output=True, timeout=10)
    except Exception as e:
        logger.debug(f"Version sync with python failed: {e}")

from BACKEND.ultra_fast_builder import UltraFastBuilder

# Initialize Fast Builder
fast_builder = UltraFastBuilder(CORE_DIR)

# Initialize builder
def prepare_builder() -> None:
    """Initialize the APK builder environment.

    This function prepares the build environment including SDK,
    keystore, and template APK. It runs once on server startup.
    """
    try:
        logger.info("Initializing Ultra Fast APK Builder environment...")
        fast_builder.prepare_environment()
        logger.info("Ultra Fast APK Builder ready!")
    except KeyboardInterrupt:
        logger.info("Build interrupted by user (Ctrl+C)")
        sys.exit(0)
    except Exception as e:
        logger.error("Failed to initialize builder", exc_info=True)

try:
    prepare_builder()
except KeyboardInterrupt:
    logger.info("Interrupted by user (Ctrl+C)")
    sys.exit(0)


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Middleware to add security headers and enforce rate limiting."""

    async def dispatch(self, request: Request, call_next):
        # Rate limiting for sensitive endpoints
        rate_limited = [
            ('/create', 'POST'),
            ('/download', 'GET'),
        ]

        for path_prefix, method in rate_limited:
            if request.url.path.startswith(path_prefix) and request.method == method:
                client_ip = get_client_ip(request)
                if not rate_limiter.is_allowed(client_ip):
                    logger.warning(f"Rate limit exceeded for IP: {client_ip}")
                    return JSONResponse({'error': 'Rate limit exceeded. Try again later.'}, status_code=429)
                break

        response = await call_next(request)

        # Add security headers
        for header, value in SECURITY_HEADERS.items():
            response.headers[header] = value
        # Remove potentially revealing headers
        if 'server' in response.headers:
            del response.headers['server']

        return response

app.add_middleware(SecurityHeadersMiddleware)


def run_build(job_id: str, apk_name: str, url: str) -> None:
    """Execute APK build in background thread.

    This function runs the build process, updating job status
    and progress throughout. It's called from a separate thread.

    Args:
        job_id: Unique identifier for this build job
        apk_name: Name for the output APK file
        url: Website URL to embed in the APK
    """
    jobs[job_id]['status'] = 'running'
    jobs[job_id]['progress'] = 0

    # Ensure apk_name ends with .apk
    if not apk_name.endswith('.apk'):
        apk_name += '.apk'

    # Sanitize filename for safe filesystem and URL handling
    apk_name = secure_filename(apk_name)
    jobs[job_id]['filename'] = apk_name

    def update_progress(p: int) -> None:
        jobs[job_id]['progress'] = p

    try:
        logger.info(f"Starting build for {apk_name} ({url})")
        output_path = fast_builder.build(url, apk_name, job_id, progress_callback=update_progress)

        if os.path.exists(output_path):
            jobs[job_id]['status'] = 'completed'
            jobs[job_id]['progress'] = 100
            logger.info(f"Build completed: {apk_name}")
        else:
            raise FileNotFoundError("Output file not found")

    except Exception as e:
        logger.error(f"Build error for job {job_id}: {e}", exc_info=True)
        jobs[job_id]['status'] = 'failed'
        jobs[job_id]['error'] = str(e)

def verify_signature(payload: bytes, signature: str) -> bool:
    """Verify GitHub webhook signature with strict validation.

    Args:
        payload: Raw request body bytes
        signature: X-Hub-Signature-256 header value

    Returns:
        True if signature is valid, False otherwise
    """
    if not WEBHOOK_SECRET:
        logger.warning("Webhook secret not configured - rejecting request")
        return False
    if not signature:
        logger.warning("Missing webhook signature")
        return False
    if not signature.startswith('sha256='):
        logger.warning("Invalid webhook signature format")
        return False
    expected = "sha256=" + hmac.new(
        WEBHOOK_SECRET.encode(), payload, hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature)

def delete_file_later(filepath: str, delay: int = 3) -> None:
    """Schedule file deletion after a delay.

    Spawns a background thread that waits and then deletes the file.
    Also removes the .idsig signature file if present.

    Args:
        filepath: Path to file to delete
        delay: Seconds to wait before deletion (default: 3)
    """
    def delayed_delete() -> None:
        time.sleep(delay)
        # Delete main file - use try-except to avoid TOCTOU race condition
        try:
            os.remove(filepath)
            logger.debug(f"Deleted {filepath}")
        except FileNotFoundError:
            logger.debug(f"File already deleted: {filepath}")
        except OSError as e:
            logger.error(f"Error deleting {filepath}: {e}")

        # Also delete the .idsig file generated by apksigner
        idsig_path = filepath + ".idsig"
        try:
            os.remove(idsig_path)
            logger.debug(f"Deleted {idsig_path}")
        except FileNotFoundError:
            pass  # .idsig is optional, may not exist
        except OSError as e:
            logger.error(f"Error deleting {idsig_path}: {e}")

    threading.Thread(target=delayed_delete, daemon=True).start()

@app.get('/favicon.ico', status_code=204)
async def favicon():
    return Response(status_code=204)

@app.get('/', response_class=HTMLResponse)
async def index(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})

@app.post('/create')
async def create(request: Request):
    data = await request.json()

    # Validate and sanitize inputs
    try:
        apk_name = sanitize_app_name(data.get('apk_name', ''))
        url = validate_url(data.get('url', ''))
    except ValueError as e:
        return JSONResponse({'error': str(e)}, status_code=400)

    job_id = str(uuid.uuid4())
    jobs[job_id] = {
        'status': 'pending',
        'apk_name': apk_name,
        'url': url,
        'start_time': time.time()
    }

    thread = threading.Thread(target=run_build, args=(job_id, apk_name, url))
    thread.start()

    return JSONResponse({'job_id': job_id})

@app.get('/status/{job_id}')
async def status(job_id: str):
    job = jobs.get(job_id)
    if not job:
        return JSONResponse({'error': 'Job not found'}, status_code=404)

    response = {
        'status': job['status'],
        'progress': job.get('progress', 0)
    }

    if job['status'] == 'completed':
        response['download_url'] = f"/download/{job_id}/{job['filename']}"

    return JSONResponse(response)

@app.get('/download/{job_id}/{filename}')
async def download(job_id: str, filename: str):
    # Verify job exists and is completed
    job = jobs.get(job_id)
    if not job or job.get('status') != 'completed':
        return JSONResponse({'error': 'Job not found or not completed'}, status_code=404)

    # Validate filename matches expected filename for this job
    expected_filename = job.get('filename')

    try:
        safe_name = secure_filename(filename)
        if safe_name != expected_filename:
            return JSONResponse({'error': 'Access denied'}, status_code=403)

        filepath = os.path.join(OUTPUT_DIR, safe_name)
        filepath = validate_file_path(filepath, OUTPUT_DIR)
    except ValueError:
        return JSONResponse({'error': 'Access denied'}, status_code=403)

    if not os.path.exists(filepath):
        return JSONResponse({'error': 'File not found'}, status_code=404)

    # Schedule deletion after download
    delete_file_later(filepath)

    return FileResponse(filepath, filename=safe_name)

@app.post("/webhook")
async def webhook(request: Request):
    """Handle GitHub webhook for auto-update.

    Verifies webhook signature and triggers git pull on valid push events.
    Automatically reloads uvicorn workers after update.
    """
    body = await request.body()
    signature = request.headers.get("X-Hub-Signature-256", "")
    if not verify_signature(body, signature):
        return Response("Forbidden", status_code=403)

    if request.headers.get("X-GitHub-Event") == "push":
        payload = await request.json()
        ref = payload.get("ref")
        if ref != "refs/heads/master":
            return Response("Ignored", status_code=200)

        logger.info("Webhook received: updating from master...")
        try:
            subprocess.run(["git", "fetch", "origin"], cwd="/app", check=True, capture_output=True, timeout=30)
            subprocess.run(["git", "reset", "--hard", "origin/master"], cwd="/app", check=True, capture_output=True, timeout=30)
            subprocess.run(["python3", "TOOLS/sync_version.py"], cwd="/app", check=True, capture_output=True, timeout=30)
            logger.info("Git update successful, reloading workers...")
            # Send SIGHUP to PID 1 for graceful reload
            os.kill(1, signal.SIGHUP) # type: ignore
        except subprocess.TimeoutExpired:
            logger.error("Git operation timed out")
            return Response("Update timed out", status_code=500)
        except subprocess.CalledProcessError as e:
            logger.error(f"Git update failed: {e.stderr.decode() if e.stderr else str(e)}")
            return Response("Update failed", status_code=500)
        except OSError as e:
            logger.error(f"Failed to reload workers: {e}")
            return Response("Reload failed", status_code=500)
    return Response("OK", status_code=200)

if __name__ == '__main__':
    import uvicorn

    # Sync version badge on startup
    subprocess.run(["python", "TOOLS/sync_version.py"])

    # Ensure output directory exists
    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)

    uvicorn.run(app, host='0.0.0.0', port=5001)
