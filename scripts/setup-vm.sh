#!/bin/bash

# K3s Setup and Update Script
# Handles fresh installs and updates for existing K3s clusters

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root. Run as a regular user with sudo privileges."
    fi
}

# Update system packages
update_system() {
    log "Updating system packages..."
    
    sudo apt update
    sudo apt upgrade -y
    sudo apt autoremove -y
    sudo apt autoclean
    
    # Install essential packages
    sudo apt install -y \
        curl \
        wget \
        git \
        htop \
        vim \
        unzip \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        jq \
        tree
    
    success "System updated and essential packages installed"
}

# Check if K3s is installed
check_k3s_installed() {
    if command -v k3s >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Get current K3s version
get_k3s_version() {
    if check_k3s_installed; then
        k3s --version | head -n1 | awk '{print $3}' | sed 's/+k3s.*//'
    else
        echo "not_installed"
    fi
}

# Get latest K3s version from GitHub
get_latest_k3s_version() {
    curl -s https://api.github.com/repos/k3s-io/k3s/releases/latest | jq -r .tag_name
}

# Install K3s
install_k3s() {
    log "Installing K3s..."
    
    # Download and run K3s installer
    curl -sfL https://get.k3s.io | sh -s - \
        --write-kubeconfig-mode 644 \
        --disable traefik \
        --disable servicelb \
        --node-name $(hostname)
    
    # Wait for K3s to be ready
    log "Waiting for K3s to be ready..."
    timeout=60
    while [ $timeout -gt 0 ]; do
        if sudo k3s kubectl get nodes >/dev/null 2>&1; then
            break
        fi
        sleep 2
        ((timeout--))
    done
    
    if [ $timeout -eq 0 ]; then
        error "K3s failed to start within 120 seconds"
    fi
    
    success "K3s installed successfully"
}

# Update K3s
update_k3s() {
    log "Updating K3s..."
    
    # Stop K3s service
    sudo systemctl stop k3s
    
    # Download and run K3s installer (updates in place)
    curl -sfL https://get.k3s.io | sh -s - \
        --write-kubeconfig-mode 644 \
        --disable traefik \
        --disable servicelb \
        --node-name $(hostname)
    
    # Wait for K3s to be ready
    log "Waiting for K3s to be ready after update..."
    timeout=60
    while [ $timeout -gt 0 ]; do
        if sudo k3s kubectl get nodes >/dev/null 2>&1; then
            break
        fi
        sleep 2
        ((timeout--))
    done
    
    if [ $timeout -eq 0 ]; then
        error "K3s failed to start after update within 120 seconds"
    fi
    
    success "K3s updated successfully"
}

# Setup kubectl alias and completion
setup_kubectl() {
    log "Setting up kubectl access..."
    
    # Create .kube directory if it doesn't exist
    mkdir -p ~/.kube
    
    # Copy K3s kubeconfig
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(whoami):$(whoami) ~/.kube/config
    chmod 600 ~/.kube/config
    
    # Add kubectl alias and completion to bashrc if not already present
    if ! grep -q "alias k=" ~/.bashrc; then
        echo "" >> ~/.bashrc
        echo "# Kubernetes aliases" >> ~/.bashrc
        echo "alias k='kubectl'" >> ~/.bashrc
        echo "alias kgp='kubectl get pods'" >> ~/.bashrc
        echo "alias kgs='kubectl get svc'" >> ~/.bashrc
        echo "alias kgn='kubectl get nodes'" >> ~/.bashrc
    fi
    
    # Install kubectl completion
    if ! grep -q "kubectl completion bash" ~/.bashrc; then
        echo "source <(kubectl completion bash)" >> ~/.bashrc
        echo "complete -F __start_kubectl k" >> ~/.bashrc
    fi
    
    success "kubectl configured with aliases and completion"
}

# Verify K3s installation
verify_k3s() {
    log "Verifying K3s installation..."
    
    # Check if node is ready
    if ! sudo k3s kubectl get nodes | grep -q "Ready"; then
        error "K3s node is not in Ready state"
    fi
    
    # Check if system pods are running
    local system_pods=$(sudo k3s kubectl get pods -n kube-system --no-headers | wc -l)
    if [ $system_pods -lt 3 ]; then
        warn "Only $system_pods system pods running, cluster may still be initializing"
    fi
    
    # Display cluster info
    log "Cluster information:"
    sudo k3s kubectl get nodes -o wide
    echo ""
    log "System pods:"
    sudo k3s kubectl get pods -n kube-system
    
    success "K3s verification completed"
}

# Main execution
main() {
    log "Starting K3s setup script..."
    
    check_root
    update_system
    
    current_version=$(get_k3s_version)
    latest_version=$(get_latest_k3s_version)
    
    log "Current K3s version: $current_version"
    log "Latest K3s version: $latest_version"
    
    if [ "$current_version" = "not_installed" ]; then
        log "K3s not found, performing fresh installation..."
        install_k3s
        setup_kubectl
        verify_k3s
    elif [ "$current_version" != "$latest_version" ]; then
        log "K3s update available: $current_version -> $latest_version"
        read -p "Do you want to update K3s? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            update_k3s
            verify_k3s
        else
            log "Skipping K3s update"
        fi
    else
        success "K3s is already up to date (version $current_version)"
        verify_k3s
    fi
    
    success "Script completed successfully!"
    log "You may need to run 'source ~/.bashrc' or start a new shell to use kubectl aliases"
    log "Test your cluster with: kubectl get nodes"
}

# Run main function
main "$@"