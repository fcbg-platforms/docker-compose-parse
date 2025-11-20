#!/bin/bash
set -e

# Load environment variables
if [ ! -f .env ]; then
    echo "Error: .env file not found. Please create one from .env.example"
    exit 1
fi

source .env

VM_NAME="${VM_NAME:-parse-server-vm}"
VM_DNS_LABEL="${VM_DNS_LABEL:-parse-vm-prod}"

# Get VM FQDN
VM_FQDN="${VM_DNS_LABEL}.${AZURE_REGION}.cloudapp.azure.com"

echo "=========================================="
echo "Setting up Parse Server VM"
echo "=========================================="
echo "VM FQDN: $VM_FQDN"
echo "This script will:"
echo "  1. Install Docker and Docker Compose"
echo "  2. Format and mount the data disk"
echo "  3. Create directory structure"
echo "  4. Configure auto-start services"
echo "=========================================="
echo ""

# Create setup script to run on VM
cat > /tmp/vm-setup-remote.sh << 'REMOTE_SCRIPT'
#!/bin/bash
set -e

echo "Starting VM setup..."

# Update system
echo "Updating system packages..."
sudo apt-get update
sudo apt-get upgrade -y

# Install Docker
echo "Installing Docker..."
if ! command -v docker &> /dev/null; then
    # Add Docker's official GPG key
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Add current user to docker group
    sudo usermod -aG docker $USER

    echo "Docker installed successfully"
else
    echo "Docker already installed"
fi

# Enable Docker to start on boot
sudo systemctl enable docker
sudo systemctl start docker

# Find and format data disk
echo "Setting up data disk..."
DATA_DISK=$(lsblk -d -n -o NAME,SIZE | grep "32G" | awk '{print $1}' | head -n 1)

if [ -z "$DATA_DISK" ]; then
    echo "Warning: Could not automatically detect 32GB data disk"
    echo "Available disks:"
    lsblk
    echo "Please manually identify the data disk and format it"
else
    echo "Found data disk: /dev/$DATA_DISK"

    # Check if disk is already formatted
    if ! sudo blkid /dev/$DATA_DISK &> /dev/null; then
        echo "Formatting disk..."
        sudo mkfs.ext4 /dev/$DATA_DISK
    else
        echo "Disk already formatted"
    fi

    # Create mount point
    sudo mkdir -p /mnt/parse-data

    # Get UUID of the disk
    DISK_UUID=$(sudo blkid -s UUID -o value /dev/$DATA_DISK)

    # Add to fstab if not already present
    if ! grep -q "$DISK_UUID" /etc/fstab; then
        echo "UUID=$DISK_UUID /mnt/parse-data ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
        echo "Added disk to /etc/fstab for automatic mounting"
    fi

    # Mount the disk
    sudo mount -a
    echo "Data disk mounted at /mnt/parse-data"
fi

# Create directory structure for Parse Server
echo "Creating directory structure..."
sudo mkdir -p /mnt/parse-data/mongodb
sudo mkdir -p /mnt/parse-data/mongo-config
sudo mkdir -p /mnt/parse-data/config-vol
sudo mkdir -p /home/azureuser/parse-server

# Set permissions
sudo chown -R azureuser:azureuser /home/azureuser/parse-server
sudo chmod -R 755 /mnt/parse-data

# Create systemd service for Parse Server stack
echo "Creating systemd service for auto-start..."
sudo tee /etc/systemd/system/parse-stack.service > /dev/null << 'EOF'
[Unit]
Description=Parse Server Docker Compose Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/azureuser/parse-server
ExecStart=/usr/bin/docker compose -f docker-compose.production.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.production.yml down
User=azureuser

[Install]
WantedBy=multi-user.target
EOF

# Enable the service (but don't start it yet, as we need to deploy files first)
sudo systemctl daemon-reload
sudo systemctl enable parse-stack.service

# Configure Docker log rotation
echo "Configuring Docker log rotation..."
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

sudo systemctl restart docker

# Install useful utilities
echo "Installing additional utilities..."
sudo apt-get install -y htop jq ncdu

echo ""
echo "=========================================="
echo "VM Setup Complete!"
echo "=========================================="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker compose version)"
echo "Data disk mounted at: /mnt/parse-data"
echo "Parse Server directory: /home/azureuser/parse-server"
echo ""
echo "Note: You may need to log out and back in for Docker group"
echo "permissions to take effect, or use 'newgrp docker'"
echo "=========================================="

REMOTE_SCRIPT

# Copy and execute the setup script on VM
echo "Connecting to VM and running setup..."
scp -o StrictHostKeyChecking=no /tmp/vm-setup-remote.sh azureuser@${VM_FQDN}:/tmp/
ssh -o StrictHostKeyChecking=no azureuser@${VM_FQDN} 'bash /tmp/vm-setup-remote.sh'

# Cleanup
rm /tmp/vm-setup-remote.sh

echo ""
echo "=========================================="
echo "VM Setup Complete!"
echo "=========================================="
echo "Next step: Run ./deploy-to-vm.sh to deploy the Parse Server stack"
echo "=========================================="
