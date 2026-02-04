"""Flask web server for Android-WebView-Auto-Builder.

This module provides the REST API for creating Android APKs from URLs.
It handles job management, build orchestration, and file delivery.

Endpoints:
    GET /: Web dashboard
    POST /create: Create new APK build job
    GET /status/<job_id>: Check job status
    GET /download/<job_id>/<filename>: Download completed APK
    POST /webhook: GitHub webhook for auto-update
"""

import hashlib
import hmac
import os
import subprocess
import sys
import threading
import time
import uuid
from typing import Optional, Dict, Any, Tuple, Union

from flask import Flask, render_template, request, jsonify, send_file, Response

from logging_config import setup_logging, get_logger
from security import (
    ThreadSafeJobs,
    RateLimiter,
    sanitize_app_name,
    validate_url,
    secure_filename,
    validate_file_path,
    add_security_headers,
)

# Initialize logging
setup_logging()
logger = get_logger(__name__)

app = Flask(__name__)

# Configuration
CORE_DIR = os.path.join(os.getcwd(), 'CORE')
OUTPUT_DIR = os.path.join(os.getcwd(), 'FINISHED_HERE')
BUILD_SCRIPT = os.path.join(CORE_DIR, 'linux_mac_build_apk.sh')

# Webhook configuration for auto-update
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "")
BRANCH = os.environ.get("BRANCH", "master")

# Thread-safe job storage
jobs = ThreadSafeJobs()

# Rate limiter: 10 requests per minute per IP
rate_limiter = RateLimiter(max_requests=10, window_seconds=60)

# Sync version badge on module load (works with gunicorn)
try:
    subprocess.run(["python3", "TOOLS/sync_version.py"], capture_output=True)
except Exception:
    try:
        subprocess.run(["python", "TOOLS/sync_version.py"], capture_output=True)
    except Exception:
        pass

from CORE.ultra_fast_builder import UltraFastBuilder

# Initialize Fast Builder
fast_builder = UltraFastBuilder(CORE_DIR)

# Initialize builder (with --preload, this runs once before workers fork)
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
        print("\n\nBuild interrupted by user (Ctrl+C)")
        sys.exit(0)
    except Exception as e:
        logger.error("Failed to initialize builder", exc_info=True)

try:
    prepare_builder()
except KeyboardInterrupt:
    print("\n\nInterrupted by user (Ctrl+C)")
    sys.exit(0)


@app.before_request
def before_request_handler():
    """Rate limiting for /create endpoint."""
    if request.path == '/create' and request.method == 'POST':
        client_ip = request.headers.get('X-Forwarded-For', request.remote_addr)
        if client_ip:
            client_ip = client_ip.split(',')[0].strip()
        if not rate_limiter.is_allowed(client_ip):
            return jsonify({'error': 'Rate limit exceeded. Try again later.'}), 429


@app.after_request
def after_request_handler(response):
    """Add security headers to all responses."""
    return add_security_headers(response)


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
        try:
            if os.path.exists(filepath):
                os.remove(filepath)
                logger.debug(f"Deleted {filepath}")

            # Also delete the .idsig file generated by apksigner
            idsig_path = filepath + ".idsig"
            if os.path.exists(idsig_path):
                os.remove(idsig_path)
                logger.debug(f"Deleted {idsig_path}")
        except Exception as e:
            logger.error(f"Error deleting {filepath}: {e}")

    threading.Thread(target=delayed_delete, daemon=True).start()

@app.route('/favicon.ico')
def favicon():
    return '', 204

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/create', methods=['POST'])
def create():
    data = request.json or {}

    # Validate and sanitize inputs
    try:
        apk_name = sanitize_app_name(data.get('apk_name', ''))
        url = validate_url(data.get('url', ''))
    except ValueError as e:
        return jsonify({'error': str(e)}), 400

    job_id = str(uuid.uuid4())
    jobs[job_id] = {
        'status': 'pending',
        'apk_name': apk_name,
        'url': url,
        'start_time': time.time()
    }
    
    thread = threading.Thread(target=run_build, args=(job_id, apk_name, url))
    thread.start()
    
    return jsonify({'job_id': job_id})

@app.route('/status/<job_id>')
def status(job_id):
    job = jobs.get(job_id)
    if not job:
        return jsonify({'error': 'Job not found'}), 404
        
    response = {
        'status': job['status'],
        'progress': job.get('progress', 0)
    }
    
    if job['status'] == 'completed':
        response['download_url'] = f"/download/{job_id}/{job['filename']}"

    return jsonify(response)

@app.route('/download/<job_id>/<filename>')
def download(job_id, filename):
    # Verify job exists and is completed
    job = jobs.get(job_id)
    if not job or job.get('status') != 'completed':
        return jsonify({'error': 'Job not found or not completed'}), 404

    # Validate filename matches expected filename for this job
    expected_filename = job.get('filename')

    try:
        safe_name = secure_filename(filename)
        if safe_name != expected_filename:
            return jsonify({'error': 'Access denied'}), 403

        filepath = os.path.join(OUTPUT_DIR, safe_name)
        filepath = validate_file_path(filepath, OUTPUT_DIR)
    except ValueError:
        return jsonify({'error': 'Access denied'}), 403

    if not os.path.exists(filepath):
        return jsonify({'error': 'File not found'}), 404

    # Schedule deletion after download
    delete_file_later(filepath)

    return send_file(filepath, as_attachment=True)

@app.route("/webhook", methods=["POST"])
def webhook() -> Tuple[str, int]:
    """Handle GitHub webhook for auto-update.

    Verifies webhook signature and triggers git pull on valid push events.
    Automatically reloads gunicorn workers after update.

    Returns:
        Tuple of response message and HTTP status code
    """
    signature = request.headers.get("X-Hub-Signature-256", "")
    if not verify_signature(request.data, signature):
        return "Forbidden", 403

    if request.headers.get("X-GitHub-Event") == "push":
        payload = request.get_json(silent=True) or {}
        ref = payload.get("ref")
        if ref != f"refs/heads/{BRANCH}":
            return "Ignored", 200

        logger.info(f"Webhook received: updating from {BRANCH}...")
        try:
            subprocess.run(["git", "fetch", "origin"], cwd="/app", check=True, capture_output=True)
            subprocess.run(["git", "reset", "--hard", f"origin/{BRANCH}"], cwd="/app", check=True, capture_output=True)
            subprocess.run(["python3", "TOOLS/sync_version.py"], cwd="/app", check=True, capture_output=True)
            logger.info("Git update successful, reloading workers...")
            os.kill(1, 1)
        except subprocess.CalledProcessError as e:
            logger.error(f"Git update failed: {e.stderr.decode() if e.stderr else str(e)}")
            return "Update failed", 500
    return "OK", 200

if __name__ == '__main__':
    # Sync version badge on startup
    subprocess.run(["python", "TOOLS/sync_version.py"])

    # Ensure output directory exists
    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)

    app.run(host='0.0.0.0', port=5001)
