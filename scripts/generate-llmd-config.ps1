# generate-llmd-config.ps1 - Complete detection and configuration generator for Windows
# Run this in PowerShell as Administrator

param(
    [string]$Owner = "user",
    [string]$Location = "home",
    [string]$OutputFile = "worker-config.yaml"
)

Write-Host "===================================" -ForegroundColor Cyan
Write-Host "LLM-D Worker Configuration Generator" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan

# Function to get GPU information
function Get-GPUInfo {
    $gpuInfo = @{}

    # Check for NVIDIA GPU
    $nvidiaPath = "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
    $nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue

    if ($nvidiaSmi -or (Test-Path $nvidiaPath)) {
        if ($nvidiaSmi) {
            $smiPath = "nvidia-smi"
        } else {
            $smiPath = $nvidiaPath
        }

        # Get GPU information
        $gpuData = & $smiPath --query-gpu=name,memory.total --format=csv,noheader

        if ($gpuData) {
            $parts = $gpuData -split ','
            $gpuInfo.Name = $parts[0].Trim()
            $memoryStr = $parts[1].Trim()
            $memoryMB = [int]($memoryStr -replace ' MiB', '')
            $gpuInfo.MemoryGB = [math]::Round($memoryMB / 1024, 1)
            $gpuInfo.Type = "nvidia"

            Write-Host "`nDetected GPU: $($gpuInfo.Name)" -ForegroundColor Green
            Write-Host "GPU Memory: $($gpuInfo.MemoryGB) GB" -ForegroundColor Green

            return $gpuInfo
        }
    }

    # Check for AMD GPU via WMI
    $videoControllers = Get-WmiObject Win32_VideoController
    foreach ($controller in $videoControllers) {
        if ($controller.Name -like "*AMD*" -or $controller.Name -like "*Radeon*") {
            $gpuInfo.Name = $controller.Name
            $gpuInfo.MemoryGB = [math]::Round($controller.AdapterRAM / 1GB, 1)
            $gpuInfo.Type = "amd"

            Write-Host "`nDetected GPU: $($gpuInfo.Name)" -ForegroundColor Green
            Write-Host "GPU Memory: $($gpuInfo.MemoryGB) GB (estimated)" -ForegroundColor Yellow

            return $gpuInfo
        }
    }

    Write-Host "`nNo dedicated GPU detected" -ForegroundColor Red
    return $null
}

# Function to get system information
function Get-SystemInfo {
    $system = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor

    $sysInfo = @{
        RAMGb = [math]::Round($system.TotalPhysicalMemory / 1GB, 0)
        CPUCores = $cpu.NumberOfCores
        CPUThreads = $cpu.NumberOfLogicalProcessors
        Hostname = $env:COMPUTERNAME
    }

    Write-Host "`nSystem Information:" -ForegroundColor Cyan
    Write-Host "  RAM: $($sysInfo.RAMGb) GB" -ForegroundColor White
    Write-Host "  CPU Cores: $($sysInfo.CPUCores) (Threads: $($sysInfo.CPUThreads))" -ForegroundColor White

    return $sysInfo
}

# Function to determine GPU tier
function Get-GPUTier {
    param([float]$MemoryGB)

    if ($MemoryGB -ge 24) { return 'high-end' }
    elseif ($MemoryGB -ge 12) { return 'mid-range' }
    elseif ($MemoryGB -ge 8) { return 'entry-level' }
    else { return 'budget' }
}

# Function to get configuration parameters based on tier
function Get-TierConfig {
    param([string]$Tier, [hashtable]$SystemInfo)

    $configs = @{
        'high-end' = @{
            MemoryFraction = 0.9
            MaxLoadedModels = 2
            BatchSize = 8
            MaxSequences = 4
            Quantization = 'none'
            CPUCores = [math]::Min($SystemInfo.CPUCores, 16)
            MemoryLimitGB = [math]::Min([int]($SystemInfo.RAMGb * 0.6), 64)
            PreloadModels = @('llama-3.2-70b')
            RecommendedModels = @(
                'llama-3.2-70b (full precision)',
                'qwen-2.5-72b (full precision)',
                'mixtral-8x7b (full precision)',
                'deepseek-coder-33b (full precision)'
            )
        }
        'mid-range' = @{
            MemoryFraction = 0.85
            MaxLoadedModels = 1
            BatchSize = 4
            MaxSequences = 2
            Quantization = 'int8'
            CPUCores = [math]::Min($SystemInfo.CPUCores, 8)
            MemoryLimitGB = [math]::Min([int]($SystemInfo.RAMGb * 0.5), 32)
            PreloadModels = @('mistral-22b')
            RecommendedModels = @(
                'llama-3.2-70b (int8 quantized)',
                'mistral-22b (int8 quantized)',
                'deepseek-coder-33b (int8 quantized)',
                'llama-3.2-13b (full precision)'
            )
        }
        'entry-level' = @{
            MemoryFraction = 0.8
            MaxLoadedModels = 1
            BatchSize = 2
            MaxSequences = 1
            Quantization = 'int4'
            CPUCores = [math]::Min($SystemInfo.CPUCores, 4)
            MemoryLimitGB = [math]::Min([int]($SystemInfo.RAMGb * 0.4), 16)
            PreloadModels = @()
            RecommendedModels = @(
                'mistral-22b (int4 quantized)',
                'llama-3.2-13b (int8 quantized)',
                'llama-3.2-7b (full precision)',
                'deepseek-coder-6.7b (full precision)'
            )
        }
        'budget' = @{
            MemoryFraction = 0.7
            MaxLoadedModels = 1
            BatchSize = 1
            MaxSequences = 1
            Quantization = 'int4'
            CPUCores = [math]::Min($SystemInfo.CPUCores, 2)
            MemoryLimitGB = [math]::Min([int]($SystemInfo.RAMGb * 0.3), 8)
            PreloadModels = @()
            RecommendedModels = @(
                'llama-3.2-7b (int4 quantized)',
                'mistral-7b (int4 quantized)',
                'phi-2 (full precision)',
                'tinyllama-1.1b (full precision)'
            )
        }
    }

    return $configs[$Tier]
}

# Function to generate YAML configuration
function New-WorkerConfig {
    param(
        [hashtable]$GPUInfo,
        [hashtable]$SystemInfo,
        [string]$Owner,
        [string]$Location
    )

    if (-not $GPUInfo) {
        # CPU-only configuration
        $config = @"
# LLM-D Worker Configuration (CPU-only)
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Host: $($SystemInfo.Hostname)

worker:
  name: "$($SystemInfo.Hostname.ToLower())"
  labels:
    owner: "$Owner"
    gpu_type: "cpu-only"
    location: "$Location"
    platform: "windows"

  server:
    url: "https://llm-d-workers.`${SECRET_DOMAIN}"
    token: "`${LLMD_WORKER_TOKEN}"
    heartbeat_interval: 60

  resources:
    gpu:
      device_ids: []
      memory_fraction: 0
    cpu:
      cores: $([math]::Min($SystemInfo.CPUCores - 2, 8))
    memory:
      limit_gb: $([math]::Min([int]($SystemInfo.RAMGb * 0.5), 16))

  models:
    cache_dir: "C:\\llm-d\\models"
    preload: []
    max_loaded: 1
    offload_timeout: 300

  performance:
    batch_size: 1
    max_sequences: 1
    use_flash_attention: false
    quantization: "int4"
"@
        return $config
    }

    # GPU configuration
    $tier = Get-GPUTier -MemoryGB $GPUInfo.MemoryGB
    $tierConfig = Get-TierConfig -Tier $tier -SystemInfo $SystemInfo

    Write-Host "`nConfiguration Details:" -ForegroundColor Yellow
    Write-Host "  GPU Tier: $tier" -ForegroundColor White
    Write-Host "  Quantization: $($tierConfig.Quantization)" -ForegroundColor White
    Write-Host "  Max Models: $($tierConfig.MaxLoadedModels)" -ForegroundColor White
    Write-Host "  Batch Size: $($tierConfig.BatchSize)" -ForegroundColor White

    # Build preload models string
    $preloadModelsStr = ""
    if ($tierConfig.PreloadModels.Count -gt 0) {
        $preloadModelsStr = ($tierConfig.PreloadModels | ForEach-Object { "    - `"$_`"" }) -join "`n"
    }

    # Create schedule section for kids
    $scheduleSection = ""
    if ($Owner -like "kid*") {
        $scheduleSection = @"

  schedule:
    available_hours:
      - start: "09:00"
        end: "15:00"
        days: ["mon", "tue", "wed", "thu", "fri"]
      - start: "22:00"
        end: "06:00"
    priority: "low"
"@
    }

    $config = @"
# LLM-D Worker Configuration
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Host: $($SystemInfo.Hostname)
# GPU: $($GPUInfo.Name) ($($GPUInfo.MemoryGB) GB)
# Tier: $tier

worker:
  name: "$($SystemInfo.Hostname.ToLower())"
  labels:
    owner: "$Owner"
    gpu_type: "$tier"
    gpu_model: "$($GPUInfo.Name -replace ' ', '_')"
    location: "$Location"
    platform: "windows"

  server:
    url: "https://llm-d-workers.`${SECRET_DOMAIN}"
    token: "`${LLMD_WORKER_TOKEN}"
    heartbeat_interval: 30

  resources:
    gpu:
      device_ids: [0]
      memory_fraction: $($tierConfig.MemoryFraction)
    cpu:
      cores: $($tierConfig.CPUCores)
    memory:
      limit_gb: $($tierConfig.MemoryLimitGB)

  models:
    cache_dir: "C:\\llm-d\\models"
    preload:
$preloadModelsStr
    max_loaded: $($tierConfig.MaxLoadedModels)
    offload_timeout: 600

  performance:
    batch_size: $($tierConfig.BatchSize)
    max_sequences: $($tierConfig.MaxSequences)
    use_flash_attention: $(if ($tier -in @('high-end', 'mid-range')) { 'true' } else { 'false' })
    quantization: "$($tierConfig.Quantization)"

  monitoring:
    prometheus_port: 9091
    enable_gpu_metrics: true$scheduleSection

# Recommended models for this configuration:
$(($tierConfig.RecommendedModels | ForEach-Object { "# - $_" }) -join "`n")
"@

    return $config
}

# Main execution
Write-Host ""

# Get hardware information
$gpuInfo = Get-GPUInfo
$systemInfo = Get-SystemInfo

# Generate configuration
$config = New-WorkerConfig -GPUInfo $gpuInfo -SystemInfo $systemInfo -Owner $Owner -Location $Location

# Save to file
$config | Out-File -FilePath $OutputFile -Encoding UTF8

Write-Host "`n===================================" -ForegroundColor Green
Write-Host "Configuration saved to: $OutputFile" -ForegroundColor Green
Write-Host "===================================" -ForegroundColor Green

Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Review the configuration file: $OutputFile" -ForegroundColor White
Write-Host "2. Copy it to your worker-configs directory" -ForegroundColor White
Write-Host "3. Deploy the worker using the installation script" -ForegroundColor White

# Display the configuration
Write-Host "`nGenerated Configuration:" -ForegroundColor Cyan
Write-Host $config
