#!/bin/bash
set -e

# llm-d Worker Installation Script
# This script installs and configures llm-d worker on a workstation

echo "==============================================="
echo "llm-d Worker Installation Script"
echo "==============================================="

# Configuration variables
WORKER_NAME="${HOSTNAME:-llmd-worker}"
SERVER_URL="${LLMD_SERVER_URL:-https://llm-d-workers.yourdomain.com}"
WORKER_TOKEN="${LLMD_WORKER_TOKEN}"
INSTALL_DIR="${LLMD_INSTALL_DIR:-/opt/llm-d}"
DATA_DIR="${LLMD_DATA_DIR:-/var/lib/llm-d}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    if [ -f /etc/debian_version ]; then
        DISTRO="debian"
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
    else
        DISTRO="unknown"
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
else
    OS="windows"
fi

print_status "Detected OS: $OS ($DISTRO)"

# Check for NVIDIA GPU
check_gpu() {
    if command -v nvidia-smi &> /dev/null; then
        print_status "NVIDIA GPU detected"
        GPU_TYPE="nvidia"
        GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
        GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
        print_status "Found $GPU_COUNT GPU(s) with ${GPU_MEMORY}MB memory each"
    elif command -v rocm-smi &> /dev/null; then
        print_status "AMD GPU detected"
        GPU_TYPE="amd"
        GPU_COUNT=$(rocm-smi --showid | grep -c GPU)
    else
        print_warning "No GPU detected, will run in CPU mode"
        GPU_TYPE="cpu"
        GPU_COUNT=0
    fi
}

# Install dependencies
install_dependencies() {
    print_status "Installing dependencies..."

    if [ "$DISTRO" == "debian" ]; then
        apt-get update
        apt-get install -y \
            curl \
            wget \
            git \
            python3 \
            python3-pip \
            python3-venv \
            build-essential \
            cmake \
            jq

        # Install Docker if not present
        if ! command -v docker &> /dev/null; then
            print_status "Installing Docker..."
            curl -fsSL https://get.docker.com | sh
            systemctl enable docker
            systemctl start docker
        fi
    elif [ "$DISTRO" == "rhel" ]; then
        yum install -y \
            curl \
            wget \
            git \
            python3 \
            python3-pip \
            gcc \
            gcc-c++ \
            make \
            cmake \
            jq

        # Install Docker if not present
        if ! command -v docker &> /dev/null; then
            print_status "Installing Docker..."
            yum install -y docker
            systemctl enable docker
            systemctl start docker
        fi
    fi
}

# Install NVIDIA Container Toolkit
install_nvidia_toolkit() {
    if [ "$GPU_TYPE" == "nvidia" ]; then
        print_status "Installing NVIDIA Container Toolkit..."

        if [ "$DISTRO" == "debian" ]; then
            distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
                sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
                tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
            apt-get update
            apt-get install -y nvidia-container-toolkit
            nvidia-ctk runtime configure --runtime=docker
            systemctl restart docker
        fi

        # Test NVIDIA Docker
        print_status "Testing NVIDIA Docker support..."
        if docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi; then
            print_status "NVIDIA Docker support verified"
        else
            print_warning "NVIDIA Docker test failed, GPU support may not work"
        fi
    fi
}

# Create llm-d user and directories
setup_directories() {
    print_status "Setting up directories..."

    # Create user if not exists
    if ! id "llmd" &>/dev/null; then
        useradd -r -s /bin/bash -d $DATA_DIR llmd
        print_status "Created llmd user"
    fi

    # Create directories
    mkdir -p $INSTALL_DIR/{bin,config,scripts}
    mkdir -p $DATA_DIR/{models,cache,logs}

    # Set permissions
    chown -R llmd:llmd $INSTALL_DIR
    chown -R llmd:llmd $DATA_DIR

    print_status "Directories created"
}

# Download and install llm-d worker
install_worker() {
    print_status "Installing llm-d worker..."

    cd $INSTALL_DIR

    # Clone
    # Clone repository or download binary
   if [ -d "llm-d" ]; then
       cd llm-d
       git pull
   else
       git clone https://github.com/llm-d-ai/llm-d.git
       cd llm-d
   fi

   # Install Python dependencies
   python3 -m venv venv
   source venv/bin/activate
   pip install --upgrade pip
   pip install -r requirements.txt

   # Install additional GPU libraries if needed
   if [ "$GPU_TYPE" == "nvidia" ]; then
       pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
       pip install flash-attn --no-build-isolation
       pip install xformers
   elif [ "$GPU_TYPE" == "amd" ]; then
       pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm5.4.2
   else
       pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
   fi

   # Install inference optimization libraries
   pip install vllm accelerate bitsandbytes

   print_status "Worker installation complete"
}

# Configure worker
configure_worker() {
   print_status "Configuring worker..."

   cat > $INSTALL_DIR/config/worker-config.yaml <<EOF
worker:
 name: $WORKER_NAME
 server_url: $SERVER_URL
 token: $WORKER_TOKEN

 # Resource configuration
 resources:
   gpu_type: $GPU_TYPE
   gpu_count: ${GPU_COUNT:-0}
   gpu_memory: ${GPU_MEMORY:-0}
   cpu_cores: $(nproc)
   memory_gb: $(free -g | awk '/^Mem:/{print $2}')

 # Model settings
 models:
   cache_dir: $DATA_DIR/models
   max_loaded_models: 2
   offload_timeout: 300

 # Performance settings
 performance:
   batch_size: auto
   max_concurrent_requests: 4
   request_timeout: 600

 # Networking
 network:
   port: 8082
   bind_address: 0.0.0.0
   enable_ssl: false

 # Logging
 logging:
   level: info
   file: $DATA_DIR/logs/worker.log
   max_size: 100M
   max_files: 10
EOF

   chown llmd:llmd $INSTALL_DIR/config/worker-config.yaml
   print_status "Configuration file created"
}

# Create systemd service
create_service() {
   print_status "Creating systemd service..."

   cat > /etc/systemd/system/llm-d-worker.service <<EOF
[Unit]
Description=llm-d Worker Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=llmd
Group=llmd
WorkingDirectory=$INSTALL_DIR/llm-d
Environment="PATH=$INSTALL_DIR/llm-d/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="CUDA_VISIBLE_DEVICES=all"
ExecStart=$INSTALL_DIR/llm-d/venv/bin/python -m llmd.worker --config $INSTALL_DIR/config/worker-config.yaml
Restart=always
RestartSec=10
StandardOutput=append:$DATA_DIR/logs/worker.log
StandardError=append:$DATA_DIR/logs/worker-error.log

# Resource limits
LimitNOFILE=65536
LimitNPROC=32768
MemoryMax=80%

[Install]
WantedBy=multi-user.target
EOF

   systemctl daemon-reload
   systemctl enable llm-d-worker
   print_status "Systemd service created and enabled"
}

# Configure firewall
configure_firewall() {
   print_status "Configuring firewall..."

   if command -v ufw &> /dev/null; then
       ufw allow 8082/tcp comment 'llm-d worker'
       print_status "UFW firewall rule added"
   elif command -v firewall-cmd &> /dev/null; then
       firewall-cmd --permanent --add-port=8082/tcp
       firewall-cmd --reload
       print_status "Firewalld rule added"
   else
       print_warning "No supported firewall found, please manually open port 8082"
   fi
}

# Setup monitoring
setup_monitoring() {
   print_status "Setting up monitoring..."

   # Create monitoring script
   cat > $INSTALL_DIR/scripts/monitor.sh <<'EOF'
#!/bin/bash
# Monitoring script for llm-d worker

while true; do
   # Check if service is running
   if systemctl is-active --quiet llm-d-worker; then
       echo "$(date): Service is running"

       # Check GPU utilization if available
       if command -v nvidia-smi &> /dev/null; then
           nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader
       fi
   else
       echo "$(date): Service is not running, attempting restart"
       systemctl restart llm-d-worker
   fi

   sleep 60
done
EOF

   chmod +x $INSTALL_DIR/scripts/monitor.sh
   chown llmd:llmd $INSTALL_DIR/scripts/monitor.sh
}

# Main installation flow
main() {
   echo ""
   print_status "Starting installation..."
   echo ""

   # Check prerequisites
   if [ -z "$LLMD_WORKER_TOKEN" ]; then
       print_error "LLMD_WORKER_TOKEN environment variable is required"
       echo "Usage: LLMD_WORKER_TOKEN='your-token' LLMD_SERVER_URL='https://llm-d-workers.yourdomain.com' $0"
       exit 1
   fi

   check_gpu
   install_dependencies
   install_nvidia_toolkit
   setup_directories
   install_worker
   configure_worker
   create_service
   configure_firewall
   setup_monitoring

   print_status "Installation complete!"
   echo ""
   echo "========================================="
   echo "Installation Summary:"
   echo "========================================="
   echo "Worker Name: $WORKER_NAME"
   echo "Server URL: $SERVER_URL"
   echo "GPU Type: $GPU_TYPE"
   echo "GPU Count: ${GPU_COUNT:-0}"
   echo "Install Dir: $INSTALL_DIR"
   echo "Data Dir: $DATA_DIR"
   echo ""
   echo "To start the worker, run:"
   echo "  systemctl start llm-d-worker"
   echo ""
   echo "To check the status, run:"
   echo "  systemctl status llm-d-worker"
   echo ""
   echo "To view logs:"
   echo "  journalctl -u llm-d-worker -f"
   echo "  tail -f $DATA_DIR/logs/worker.log"
   echo ""
   echo "To enable auto-start on boot:"
   echo "  systemctl enable llm-d-worker"
   echo ""
}

# Run main function
main "$@"
