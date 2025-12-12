import os
import subprocess
import threading
import time
import uuid
import random
from flask import Flask, render_template, request, jsonify, send_file, after_this_request

app = Flask(__name__)

# Configuration
CORE_DIR = os.path.join(os.getcwd(), 'CORE')
OUTPUT_DIR = os.path.join(os.getcwd(), 'FINISHED_HERE')
JOKES_FILE = os.path.join(CORE_DIR, 'jokes.txt')
BUILD_SCRIPT = os.path.join(CORE_DIR, 'linux_mac_build_apk.sh')

# Global state to track jobs
jobs = {}

def load_jokes():
    if os.path.exists(JOKES_FILE):
        with open(JOKES_FILE, 'r', encoding='utf-8') as f:
            return [line.strip() for line in f if line.strip()]
    return ["Loading..."]

JOKES = load_jokes()

def run_build(job_id, apk_name, url):
    jobs[job_id]['status'] = 'running'
    
    # Ensure apk_name ends with .apk
    if not apk_name.endswith('.apk'):
        apk_name += '.apk'
        
    jobs[job_id]['filename'] = apk_name

    cmd = [BUILD_SCRIPT, "--name", apk_name, "--url", url, "--id", job_id]
    
    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            cwd=os.getcwd()
        )
        
        # Read output to keep buffer clear and track progress
        for line in process.stdout:
            line = line.strip()
            if line.startswith("PROGRESS:"):
                try:
                    progress = int(line.split(":")[1].strip())
                    jobs[job_id]['progress'] = progress
                except ValueError:
                    pass
            
        process.wait()
        
        if process.returncode == 0:
            jobs[job_id]['status'] = 'completed'
            jobs[job_id]['progress'] = 100
        else:
            jobs[job_id]['status'] = 'failed'
            
    except Exception as e:
        print(f"Build error: {e}")
        jobs[job_id]['status'] = 'failed'

def delete_file_later(filepath, delay=3):
    def delayed_delete():
        time.sleep(delay)
        try:
            if os.path.exists(filepath):
                os.remove(filepath)
                print(f"Deleted {filepath}")
        except Exception as e:
            print(f"Error deleting {filepath}: {e}")
            
    threading.Thread(target=delayed_delete).start()

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/create', methods=['POST'])
def create():
    data = request.json
    apk_name = data.get('apk_name')
    url = data.get('url')
    
    if not apk_name or not url:
        return jsonify({'error': 'Missing parameters'}), 400
        
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
        'progress': job.get('progress', 0),
        'joke': random.choice(JOKES)
    }
    
    if job['status'] == 'completed':
        response['download_url'] = f"/download/{job['filename']}"
        
    return jsonify(response)

@app.route('/download/<filename>')
def download(filename):
    filepath = os.path.join(OUTPUT_DIR, filename)
    
    if not os.path.exists(filepath):
        # Fallback to project root if not in OUTPUT_DIR (just in case script behavior changes)
        filepath = os.path.join(os.getcwd(), filename)
        
    if not os.path.exists(filepath):
        return "File not found", 404

    # Schedule deletion
    delete_file_later(filepath)
    
    return send_file(filepath, as_attachment=True)

if __name__ == '__main__':
    # Ensure output directory exists
    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)
        
    app.run(host='0.0.0.0', port=5001)
