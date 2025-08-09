# Get worker token from your Kubernetes cluster first
$WORKER_TOKEN = "your-token-here"

# For PC-Vengeance (RTX 4080)
cd C:\temp
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gavinmcfall/home-ops/main/kubernetes/apps/cortex/llm-d/workers/PC-Nerdz/worker-config.yaml" -OutFile "worker-config.yaml"
.\install-llmd-worker.ps1 -WorkerToken $WORKER_TOKEN -ConfigFile "worker-config.yaml"

# For PC-Vixen (RTX 4080 Super)
cd C:\temp
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gavinmcfall/home-ops/main/kubernetes/apps/cortex/llm-d/workers/PC-Vixen/worker-config.yaml" -OutFile "worker-config.yaml"
.\install-llmd-worker.ps1 -WorkerToken $WORKER_TOKEN -ConfigFile "worker-config.yaml"

# For PC-Nova (RTX 3050)
cd C:\temp
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gavinmcfall/home-ops/main/kubernetes/apps/cortex/llm-d/workers/PC-Nova/worker-config.yaml" -OutFile "worker-config.yaml"
.\install-llmd-worker.ps1 -WorkerToken $WORKER_TOKEN -ConfigFile "worker-config.yaml"

# For PC-Blaze (RTX 3050)
cd C:\temp
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gavinmcfall/home-ops/main/kubernetes/apps/cortex/llm-d/workers/PC-Blaze/worker-config.yaml" -OutFile "worker-config.yaml"
.\install-llmd-worker.ps1 -WorkerToken $WORKER_TOKEN -ConfigFile "worker-config.yaml"
