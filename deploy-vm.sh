#!/bin/bash
set -e

# Load environment variables
if [ ! -f .env ]; then
    echo "Error: .env file not found. Please create one from .env.example"
    exit 1
fi

source .env

# VM Configuration
VM_NAME="${VM_NAME:-parse-server-vm}"
VM_SIZE="${VM_SIZE:-Standard_B2s}"
VM_DISK_SIZE="${VM_DISK_SIZE:-32}"
VM_IMAGE="Ubuntu2204"
VM_DNS_LABEL="${VM_DNS_LABEL:-parse-vm-prod}"

# SSH Key Configuration
SSH_KEY_PATH="${VM_SSH_KEY_PATH:-$HOME/.ssh/id_rsa.pub}"

if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Error: SSH public key not found at $SSH_KEY_PATH"
    echo "Please update VM_SSH_KEY_PATH in .env or create an SSH key pair"
    exit 1
fi

echo "=========================================="
echo "Deploying Parse Server VM to Azure"
echo "=========================================="
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "Region: $AZURE_REGION"
echo "VM Name: $VM_NAME"
echo "VM Size: $VM_SIZE"
echo "Disk Size: ${VM_DISK_SIZE}GB"
echo "DNS Label: ${VM_DNS_LABEL}.${AZURE_REGION}.cloudapp.azure.com"
echo "=========================================="

# Check if resource group exists, create if not
if ! az group show --name "$RESOURCE_GROUP_NAME" &> /dev/null; then
    echo "Creating resource group $RESOURCE_GROUP_NAME..."
    az group create \
        --name "$RESOURCE_GROUP_NAME" \
        --location "$AZURE_REGION"
else
    echo "Resource group $RESOURCE_GROUP_NAME already exists"
fi

# Create Network Security Group with required ports
NSG_NAME="${VM_NAME}-nsg"
echo "Creating Network Security Group..."
az network nsg create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$NSG_NAME" \
    --location "$AZURE_REGION"

# Add NSG rules
echo "Configuring firewall rules..."

# SSH (port 22)
az network nsg rule create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --nsg-name "$NSG_NAME" \
    --name "Allow-SSH" \
    --priority 1000 \
    --destination-port-ranges 22 \
    --access Allow \
    --protocol Tcp \
    --description "Allow SSH access"

# Parse Server (port 1337)
az network nsg rule create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --nsg-name "$NSG_NAME" \
    --name "Allow-Parse-Server" \
    --priority 1010 \
    --destination-port-ranges 1337 \
    --access Allow \
    --protocol Tcp \
    --description "Allow Parse Server access"

# Parse Dashboard (port 4040)
az network nsg rule create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --nsg-name "$NSG_NAME" \
    --name "Allow-Parse-Dashboard" \
    --priority 1020 \
    --destination-port-ranges 4040 \
    --access Allow \
    --protocol Tcp \
    --description "Allow Parse Dashboard access"

# Create Virtual Network and Subnet
VNET_NAME="${VM_NAME}-vnet"
SUBNET_NAME="${VM_NAME}-subnet"
echo "Creating virtual network..."
az network vnet create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$VNET_NAME" \
    --address-prefix 10.0.0.0/16 \
    --subnet-name "$SUBNET_NAME" \
    --subnet-prefix 10.0.1.0/24 \
    --location "$AZURE_REGION"

# Create Public IP with DNS label
PUBLIC_IP_NAME="${VM_NAME}-ip"
echo "Creating public IP address with DNS label..."
az network public-ip create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$PUBLIC_IP_NAME" \
    --dns-name "$VM_DNS_LABEL" \
    --allocation-method Static \
    --sku Standard \
    --location "$AZURE_REGION"

# Get the FQDN
VM_FQDN=$(az network public-ip show \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$PUBLIC_IP_NAME" \
    --query dnsSettings.fqdn \
    --output tsv)

echo "VM will be accessible at: $VM_FQDN"

# Create VM
echo "Creating virtual machine (this may take a few minutes)..."
az vm create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$VM_NAME" \
    --location "$AZURE_REGION" \
    --size "$VM_SIZE" \
    --image "$VM_IMAGE" \
    --admin-username azureuser \
    --ssh-key-values "@${SSH_KEY_PATH}" \
    --public-ip-address "$PUBLIC_IP_NAME" \
    --vnet-name "$VNET_NAME" \
    --subnet "$SUBNET_NAME" \
    --nsg "$NSG_NAME" \
    --storage-sku StandardSSD_LRS \
    --os-disk-size-gb 30

# Create and attach data disk for persistent storage
DATA_DISK_NAME="${VM_NAME}-data-disk"
echo "Creating data disk for persistent storage..."
az disk create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$DATA_DISK_NAME" \
    --size-gb "$VM_DISK_SIZE" \
    --sku StandardSSD_LRS \
    --location "$AZURE_REGION"

echo "Attaching data disk to VM..."
az vm disk attach \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --vm-name "$VM_NAME" \
    --name "$DATA_DISK_NAME"

echo ""
echo "=========================================="
echo "VM Deployment Complete!"
echo "=========================================="
echo "VM Name: $VM_NAME"
echo "Public IP: $(az network public-ip show --resource-group "$RESOURCE_GROUP_NAME" --name "$PUBLIC_IP_NAME" --query ipAddress --output tsv)"
echo "FQDN: $VM_FQDN"
echo "SSH Access: ssh azureuser@$VM_FQDN"
echo ""
echo "Next steps:"
echo "1. Run ./setup-vm.sh to configure Docker and mount the data disk"
echo "2. Run ./deploy-to-vm.sh to deploy the Parse Server stack"
echo "=========================================="
