## Instructions for LLM-D Worker (Per Machine)

1.  Open Powershell
1.  If Docker Desktop is already installed and working skip to step 7
1.  Ensure WSL2 and Virtualization Features are Enabled:
    ```
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
    Restart-Computer
    ```
1.  After restarting, set WSL 2 as the default version:
    ```
    wsl --set-default-version 2
    ```
1.  Verify WSL installation:
    ```
    wsl --status
    ```
1.  Install Docker Desktop via Powershell using winget
    ```
    winget install Docker.DockerDesktop
    Restart-Computer
    ```
1.  Create the LLM-D Directory:

    ```
    mkdir "C:\llm-d"
    ```

1.  Navidate to temp directory:

    ```
    cd C:\temp
    ```

1.  Pull down the files:

    ```
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gavinmcfall/home-ops/main/kubernetes/apps/cortex/llm-d/installers/windows/docker-compose.yaml" -OutFile "C:\llm-d\docker-compose.yaml"
    ```
    ```
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gavinmcfall/home-ops/main/kubernetes/apps/cortex/llm-d/installers/windows/install-llmd-worker.ps1" -OutFile "install-llmd-worker.ps1"
    ```
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gavinmcfall/home-ops/main/kubernetes/apps/cortex/llm-d/installers/windows/deployment.ps1" -OutFile "deployment.ps1"

1.  Paste your $WORKER_TOKEN into the `deployment.ps1` file from your 1Password Secret
1.  Delete the lines from `deployment.ps1` for the non-relevant machines
1.  Allow execution of scripts in powershell
    ```
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
    ```
1.  Run deployment script
    ```
    .\deployment.ps1
    ```
