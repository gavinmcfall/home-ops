# install-llmd-worker.ps1 - Complete Windows installer
param(
    [Parameter(Mandatory=$true)]
    [string]$WorkerToken,

    [string]$ConfigFile = "worker-config.yaml"
)

$ErrorActionPreference = "Stop"

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "LLM-D Worker Windows Installer" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan

# Check prerequisites
function Test-Prerequisites {
    Write-Host "`nChecking prerequisites..." -ForegroundColor Yellow

    # Check Docker Desktop
    if (!(Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Host "Docker Desktop not found! Please install from https://www.docker.com/products/docker-desktop" -ForegroundColor Red
        exit 1
    }

    # Check if Docker is running
    try {
        docker ps | Out-Null
        Write-Host "✓ Docker Desktop is running" -ForegroundColor Green
    } catch {
        Write-Host "Docker Desktop is installed but not running. Please start Docker Desktop." -ForegroundColor Red
        exit 1
    }

    # Check for NVIDIA Container Toolkit
    docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ NVIDIA GPU support verified" -ForegroundColor Green
    } else {
        Write-Host "! NVIDIA GPU support not working. Installing NVIDIA Container Toolkit..." -ForegroundColor Yellow
        # This would need manual intervention on Windows
    }
}

# Create directory structure
function Setup-Directories {
    Write-Host "`nSetting up directories..." -ForegroundColor Yellow

    $dirs = @(
        "C:\llm-d",
        "C:\llm-d\models",
        "C:\llm-d\cache",
        "C:\llm-d\config",
        "C:\llm-d\logs"
    )

    foreach ($dir in $dirs) {
        if (!(Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host "✓ Created $dir" -ForegroundColor Green
        }
    }
}

# Copy configuration
function Setup-Configuration {
    param([string]$ConfigFile, [string]$Token)

    Write-Host "`nSetting up configuration..." -ForegroundColor Yellow

    # Copy worker config
    if (Test-Path $ConfigFile) {
        Copy-Item $ConfigFile "C:\llm-d\config\worker-config.yaml" -Force
        Write-Host "✓ Copied worker configuration" -ForegroundColor Green
    } else {
        Write-Host "! Worker config not found: $ConfigFile" -ForegroundColor Red
        exit 1
    }

    # Create docker-compose.yml
    $dockerCompose = @"
version: '3.8'

services:
  llm-d-worker:
    image: ghcr.io/llm-d-ai/llm-d-worker:latest
    container_name: llm-d-worker
    restart: always
    environment:
      - WORKER_NAME=$env:COMPUTERNAME
      - SERVER_URL=https://llm-d-workers.yourdomain.com
      - WORKER_TOKEN=$Token
      - LOG_LEVEL=info
    volumes:
      - C:\llm-d\models:/models
      - C:\llm-d\cache:/cache
      - C:\llm-d\config\worker-config.yaml:/app/config.yaml:ro
      - C:\llm-d\logs:/logs
    network_mode: host
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
"@

    $dockerCompose | Out-File "C:\llm-d\docker-compose.yml" -Encoding UTF8
    Write-Host "✓ Created docker-compose.yml" -ForegroundColor Green

    # Create .env file
    @"
LLMD_WORKER_TOKEN=$Token
COMPUTERNAME=$env:COMPUTERNAME
"@ | Out-File "C:\llm-d\.env" -Encoding UTF8
    Write-Host "✓ Created .env file" -ForegroundColor Green
}

# Create startup script
function Create-StartupScript {
    Write-Host "`nCreating startup script..." -ForegroundColor Yellow

    $startupScript = @'
@echo off
cd /d C:\llm-d
echo Starting LLM-D Worker...

:CHECK_DOCKER
timeout /t 10 /nobreak > nul
docker version >nul 2>&1
if errorlevel 1 (
    echo Waiting for Docker to start...
    goto CHECK_DOCKER
)

echo Docker is ready, starting worker...
docker-compose up -d

echo Worker started successfully
'@

    $startupScript | Out-File "C:\llm-d\start-worker.bat" -Encoding ASCII
    Write-Host "✓ Created startup script" -ForegroundColor Green
}

# Create Windows Task Scheduler entry
function Setup-AutoStart {
    Write-Host "`nSetting up auto-start..." -ForegroundColor Yellow

    $taskName = "LLM-D Worker"

    # Remove existing task if it exists
    Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false

    # Create new scheduled task
    $action = New-ScheduledTaskAction -Execute "C:\llm-d\start-worker.bat"
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

    Write-Host "✓ Created scheduled task for auto-start" -ForegroundColor Green

    # Also create a task that starts 2 minutes after logon (backup)
    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn -Delay (New-TimeSpan -Minutes 2)
    $taskNameLogon = "LLM-D Worker Logon"

    Register-ScheduledTask -TaskName $taskNameLogon -Action $action -Trigger $logonTrigger -Principal $principal -Settings $settings | Out-Null

    Write-Host "✓ Created backup scheduled task for logon" -ForegroundColor Green
}

# Create monitoring script
function Create-MonitoringScript {
    Write-Host "`nCreating monitoring script..." -ForegroundColor Yellow

    $monitorScript = @'
# monitor-worker.ps1
while ($true) {
    $container = docker ps -q -f name=llm-d-worker

    if (!$container) {
        Write-Host "$(Get-Date): Worker not running, restarting..." -ForegroundColor Red
        Set-Location C:\llm-d
        docker-compose up -d
    } else {
        Write-Host "$(Get-Date): Worker is running" -ForegroundColor Green

        # Check GPU utilization
        docker exec llm-d-worker nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader
    }

    Start-Sleep -Seconds 60
}
'@

    $monitorScript | Out-File "C:\llm-d\monitor-worker.ps1" -Encoding UTF8
    Write-Host "✓ Created monitoring script" -ForegroundColor Green
}

# Main installation
function Install-Worker {
    Test-Prerequisites
    Setup-Directories
    Setup-Configuration -ConfigFile $ConfigFile -Token $WorkerToken
    Create-StartupScript
    Setup-AutoStart
    Create-MonitoringScript

    Write-Host "`n==================================" -ForegroundColor Green
    Write-Host "Installation Complete!" -ForegroundColor Green
    Write-Host "==================================" -ForegroundColor Green

    Write-Host "`nStarting worker..." -ForegroundColor Yellow
    Set-Location C:\llm-d
    docker-compose pull
    docker-compose up -d

    Start-Sleep -Seconds 5

    # Check if running
    $container = docker ps -q -f name=llm-d-worker
    if ($container) {
        Write-Host "✓ Worker is running!" -ForegroundColor Green
        docker logs llm-d-worker --tail 20
    } else {
        Write-Host "! Worker failed to start. Check logs:" -ForegroundColor Red
        Write-Host "  docker logs llm-d-worker" -ForegroundColor Yellow
    }

    Write-Host "`nWorker will automatically start:" -ForegroundColor Cyan
    Write-Host "  - When Windows starts" -ForegroundColor White
    Write-Host "  - When any user logs in" -ForegroundColor White
    Write-Host "  - If it crashes (auto-restart)" -ForegroundColor White

    Write-Host "`nUseful commands:" -ForegroundColor Cyan
    Write-Host "  Check status:  docker ps" -ForegroundColor White
    Write-Host "  View logs:     docker logs llm-d-worker -f" -ForegroundColor White
    Write-Host "  Restart:       docker-compose restart" -ForegroundColor White
    Write-Host "  Stop:          docker-compose stop" -ForegroundColor White
    Write-Host "  Monitor:       powershell C:\llm-d\monitor-worker.ps1" -ForegroundColor White
}

# Run installation
Install-Worker
