// ============================================
// WebGL Background Animation
// ============================================

const m4 = twgl.m4;
const gl = document.querySelector("#c").getContext("webgl");
const programInfo = twgl.createProgramInfo(gl, [
    `
    attribute vec4 position;
    attribute vec3 normal;
    uniform mat4 u_worldViewProjection;
    uniform mat4 u_worldInverseTranspose;
    varying vec3 v_normal;
    void main() {
        gl_Position = u_worldViewProjection * position;
        v_normal = (u_worldInverseTranspose * vec4(normal, 0)).xyz;
    }
    `,
    `
    precision mediump float;
    varying vec3 v_normal;
    uniform vec3 u_lightWorldPos;
    uniform vec4 u_color;
    void main() {
        vec3 normal = normalize(v_normal);
        vec3 lightDir = normalize(u_lightWorldPos);
        float light = dot(normal, lightDir) * 0.5 + 0.5;
        gl_FragColor = u_color * light;
    }
    `
]);

const arrays = {
    sphere: twgl.primitives.createSphereVertices(10, 24, 12),
    cube: twgl.primitives.createCubeVertices(15),
    cone: twgl.primitives.createTruncatedConeVertices(10, 0, 20, 24, 1),
};
const bufferInfos = {
    sphere: twgl.createBufferInfoFromArrays(gl, arrays.sphere),
    cube: twgl.createBufferInfoFromArrays(gl, arrays.cube),
    cone: twgl.createBufferInfoFromArrays(gl, arrays.cone),
};

const objects = [];
const shapes = ['sphere', 'cube', 'cone'];
const colors = [
    [0.39, 0.4, 0.95, 1],
    [0.66, 0.33, 0.97, 1],
    [0.93, 0.28, 0.6, 1]
];

for (let i = 0; i < 20; i++) {
    objects.push({
        type: shapes[Math.floor(Math.random() * shapes.length)],
        color: colors[Math.floor(Math.random() * colors.length)],
        x: (Math.random() - 0.5) * 100,
        y: (Math.random() - 0.5) * 100,
        z: (Math.random() - 0.5) * 50 - 20,
        ySpeed: (Math.random() - 0.5) * 0.05,
        rotSpeed: (Math.random() - 0.5) * 0.05,
        scale: Math.random() * 0.5 + 0.5,
    });
}

function render(time) {
    time *= 0.001;
    twgl.resizeCanvasToDisplaySize(gl.canvas);
    gl.viewport(0, 0, gl.canvas.width, gl.canvas.height);

    gl.enable(gl.DEPTH_TEST);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

    const fov = 30 * Math.PI / 180;
    const aspect = gl.canvas.clientWidth / gl.canvas.clientHeight;
    const projection = m4.perspective(fov, aspect, 0.5, 200);
    const eye = [0, 0, 100];
    const camera = m4.lookAt(eye, [0, 0, 0], [0, 1, 0]);
    const view = m4.inverse(camera);
    const viewProjection = m4.multiply(projection, view);

    gl.useProgram(programInfo.program);
    twgl.setUniforms(programInfo, { u_lightWorldPos: [1, 8, -10] });

    objects.forEach((obj) => {
        let world = m4.identity();
        world = m4.translate(world, [obj.x, obj.y + Math.sin(time + obj.x) * 5, obj.z]);
        world = m4.rotateY(world, time * obj.rotSpeed);
        world = m4.rotateX(world, time * obj.rotSpeed);
        world = m4.scale(world, [obj.scale, obj.scale, obj.scale]);

        twgl.setUniforms(programInfo, {
            u_worldViewProjection: m4.multiply(viewProjection, world),
            u_worldInverseTranspose: m4.transpose(m4.inverse(world)),
            u_color: obj.color,
        });

        twgl.setBuffersAndAttributes(gl, programInfo, bufferInfos[obj.type]);
        twgl.drawBufferInfo(gl, bufferInfos[obj.type]);
    });

    requestAnimationFrame(render);
}
requestAnimationFrame(render);

// ============================================
// APK Builder Functions
// ============================================

let pollInterval;

function shakeContainer() {
    const container = document.querySelector('.container');
    container.style.animation = 'shake 0.5s cubic-bezier(.36,.07,.19,.97) both';
    setTimeout(() => container.style.animation = '', 500);
}

async function startBuild() {
    const apkName = document.getElementById('apk-name').value.trim();
    let url = document.getElementById('url').value.trim();

    // Validate required fields
    if (!apkName || !url) {
        shakeContainer();
        return;
    }

    // Auto-prefix https:// if no protocol specified
    if (!url.includes('://')) {
        url = 'https://' + url;
        document.getElementById('url').value = url; // Update input field
    }

    // Block HTTP (only HTTPS allowed)
    if (url.toLowerCase().startsWith('http://')) {
        alert('Only HTTPS URLs are allowed for security reasons.\n\nPlease use https:// instead of http://');
        document.getElementById('url').focus();
        shakeContainer();
        return;
    }

    const inputArea = document.getElementById('input-area');
    inputArea.style.opacity = '0';
    inputArea.style.transform = 'translateY(-20px)';

    setTimeout(() => {
        inputArea.style.display = 'none';
        document.getElementById('progress-area').style.display = 'block';
    }, 300);

    try {
        const response = await fetch('/create', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ apk_name: apkName, url: url })
        });
        const data = await response.json();

        if (data.job_id) {
            localStorage.setItem('apk_build_job_id', data.job_id);
            pollStatus(data.job_id);
        } else {
            alert('Failed to start build.');
            resetUI();
        }
    } catch (error) {
        console.error('Error:', error);
        alert('An error occurred.');
        resetUI();
    }
}

function pollStatus(jobId) {
    pollInterval = setInterval(async () => {
        try {
            const response = await fetch(`/status/${jobId}`);

            if (response.status === 404) {
                clearInterval(pollInterval);
                localStorage.removeItem('apk_build_job_id');
                alert('Session expired or build not found. Please start a new build.');
                resetUI();
                return;
            }

            const data = await response.json();

            if (data.progress !== undefined) {
                document.getElementById('progress-bar').style.width = data.progress + '%';
                document.getElementById('status-text').innerText = `Building... ${data.progress}%`;
            }

            if (data.status === 'completed') {
                clearInterval(pollInterval);
                showDownload(data.download_url);
            } else if (data.status === 'failed') {
                clearInterval(pollInterval);
                localStorage.removeItem('apk_build_job_id');
                alert('Build failed.');
                resetUI();
            }
        } catch (error) {
            console.error('Error polling status:', error);
        }
    }, 4000);
}

function showDownload(url) {
    const progressArea = document.getElementById('progress-area');
    progressArea.style.opacity = '0';

    setTimeout(() => {
        progressArea.style.display = 'none';
        const downloadBtn = document.getElementById('download-btn');
        const downloadLink = document.getElementById('download-link');
        downloadLink.href = url;
        downloadBtn.style.display = 'block';
        downloadBtn.style.animation = 'fadeIn 0.5s ease-out';

        downloadBtn.onclick = () => {
            localStorage.removeItem('apk_build_job_id');
            setTimeout(() => location.reload(), 3000);
        };
    }, 300);
}

function resetUI() {
    const inputArea = document.getElementById('input-area');
    const progressArea = document.getElementById('progress-area');
    progressArea.style.display = 'none';
    inputArea.style.display = 'block';

    setTimeout(() => {
        inputArea.style.opacity = '1';
        inputArea.style.transform = 'translateY(0)';
    }, 50);

    document.getElementById('download-btn').style.display = 'none';
}

// ============================================
// Event Listeners
// ============================================

document.addEventListener('DOMContentLoaded', () => {
    // Restore session from localStorage if exists
    const savedJobId = localStorage.getItem('apk_build_job_id');
    if (savedJobId) {
        document.getElementById('input-area').style.display = 'none';
        document.getElementById('progress-area').style.display = 'block';
        pollStatus(savedJobId);
    }

    // Create button click handler (replaces onclick="startBuild()")
    document.getElementById('create-btn').addEventListener('click', startBuild);
});

window.addEventListener('load', () => {
    setTimeout(() => {
        document.getElementById('page-preloader').classList.add('hidden');
        document.querySelector('.page-content').classList.add('loaded');
    }, 100);
});
