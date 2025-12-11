$ErrorActionPreference = "Stop"
$WorkDir = "$PSScriptRoot\android_build_env"

function Remove-ItemSafe {
    param($Path)
    if (-not (Test-Path $Path)) { return }
    
    for ($i = 0; $i -lt 10; $i++) {
        try {
            Remove-Item $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }
    Write-Warning "Unable to remove $Path (File locked?)"
}

if (Test-Path $WorkDir) {
    # Forcefully stop any process running from the build directory (like the Gradle Daemon)
    Write-Host "Checking for lingering processes..." -ForegroundColor Cyan
    $Processes = Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like "*android_build_env*" }
    foreach ($Proc in $Processes) {
        Write-Host "Stopping process: $($Proc.Name) (PID: $($Proc.ProcessId))" -ForegroundColor Yellow
        Stop-Process -Id $Proc.ProcessId -Force -ErrorAction SilentlyContinue
    }
    
    # Wait a moment for locks to release
    Start-Sleep -Seconds 2

    Write-Host "Removing $WorkDir..." -ForegroundColor Cyan
    Remove-ItemSafe $WorkDir
    Write-Host "Cleanup complete." -ForegroundColor Green
} else {
    Write-Host "Nothing to clean. '$WorkDir' does not exist." -ForegroundColor Yellow
}
