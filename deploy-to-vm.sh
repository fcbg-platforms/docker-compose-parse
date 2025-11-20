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
echo "Deploying Parse Server Stack to VM"
echo "=========================================="
echo "VM FQDN: $VM_FQDN"
echo "=========================================="
echo ""

# Create temporary .env file with VM-specific configuration
echo "Creating VM-specific environment configuration..."

# URL-encode function for MongoDB password (handles special characters)
url_encode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * )               printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# URL-encode MongoDB credentials
ENCODED_USERNAME=$(url_encode "${MONGO_INITDB_ROOT_USERNAME}")
ENCODED_PASSWORD=$(url_encode "${MONGO_INITDB_ROOT_PASSWORD}")

cat > /tmp/.env.vm << EOF
# Azure Infrastructure
RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME}
AZURE_REGION=${AZURE_REGION}

# VM Configuration
VM_NAME=${VM_NAME}
VM_DNS_LABEL=${VM_DNS_LABEL}

# MongoDB Credentials
MONGO_INITDB_ROOT_USERNAME=${MONGO_INITDB_ROOT_USERNAME}
MONGO_INITDB_ROOT_PASSWORD=${MONGO_INITDB_ROOT_PASSWORD}

# Parse Server Config
PARSE_SERVER_APPLICATION_ID=${PARSE_SERVER_APPLICATION_ID}
PARSE_SERVER_MASTER_KEY=${PARSE_SERVER_MASTER_KEY}
PARSE_SERVER_DATABASE_NAME=${PARSE_SERVER_DATABASE_NAME}

# Database URI - Internal Docker network (mongodb is the container name)
# Credentials are URL-encoded to handle special characters
PARSE_SERVER_DATABASE_URI=mongodb://${ENCODED_USERNAME}:${ENCODED_PASSWORD}@mongodb:27017/${PARSE_SERVER_DATABASE_NAME}?authSource=admin

# Parse Server URL - Public VM FQDN
PARSE_SERVER_URL=http://${VM_FQDN}:1337/parse

# Parse Server Additional Config
PARSE_SERVER_MASTER_KEY_IPS=${PARSE_SERVER_MASTER_KEY_IPS:-}

# Parse Dashboard Config
PARSE_DASHBOARD_APP_NAME=${PARSE_DASHBOARD_APP_NAME}
PARSE_DASHBOARD_USER_ID=${PARSE_DASHBOARD_USER_ID}
PARSE_DASHBOARD_USER_PASSWORD=${PARSE_DASHBOARD_USER_PASSWORD}
PARSE_DASHBOARD_ALLOW_INSECURE_HTTP=${PARSE_DASHBOARD_ALLOW_INSECURE_HTTP}
EOF

echo "Transferring files to VM..."

# Create remote directory if it doesn't exist
ssh -o StrictHostKeyChecking=no azureuser@${VM_FQDN} 'mkdir -p ~/parse-server'

# Transfer docker-compose file
scp -o StrictHostKeyChecking=no docker-compose.production.yml azureuser@${VM_FQDN}:~/parse-server/

# Transfer environment file
scp -o StrictHostKeyChecking=no /tmp/.env.vm azureuser@${VM_FQDN}:~/parse-server/.env

# Clean up local temp file
rm /tmp/.env.vm

echo "Starting Parse Server stack on VM..."

# Deploy the stack
ssh -o StrictHostKeyChecking=no azureuser@${VM_FQDN} << 'REMOTE_DEPLOY'
cd ~/parse-server

# Pull latest images
echo "Pulling Docker images..."
docker compose -f docker-compose.production.yml pull

# Stop existing containers if any
if docker compose -f docker-compose.production.yml ps --quiet | grep -q .; then
    echo "Stopping existing containers..."
    docker compose -f docker-compose.production.yml down
fi

# Start the stack
echo "Starting Parse Server stack..."
docker compose -f docker-compose.production.yml up -d

# Wait for services to be healthy
echo "Waiting for services to start..."
sleep 10

# Check container status
echo ""
echo "Container Status:"
docker compose -f docker-compose.production.yml ps

# Check Parse Server health
echo ""
echo "Checking Parse Server health..."
for i in {1..30}; do
    if curl -s http://localhost:1337/parse/health > /dev/null; then
        echo "Parse Server is healthy!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "Warning: Parse Server health check timed out"
        echo "Checking logs:"
        docker compose -f docker-compose.production.yml logs parse-server --tail 20
    fi
    sleep 2
done

# Check Parse Dashboard
echo ""
echo "Checking Parse Dashboard..."
for i in {1..15}; do
    if curl -s http://localhost:4040 > /dev/null; then
        echo "Parse Dashboard is accessible!"
        break
    fi
    if [ $i -eq 15 ]; then
        echo "Warning: Parse Dashboard check timed out"
    fi
    sleep 2
done

REMOTE_DEPLOY

# Get the VM's public IP
VM_IP=$(az network public-ip show \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "${VM_NAME}-ip" \
    --query ipAddress \
    --output tsv)

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Parse Server is now running on Azure VM:"
echo ""
echo "  Parse Server API:"
echo "    http://${VM_FQDN}:1337/parse"
echo "    http://${VM_IP}:1337/parse"
echo ""
echo "  Parse Dashboard:"
echo "    http://${VM_FQDN}:4040"
echo "    http://${VM_IP}:4040"
echo ""
echo "  Dashboard Login:"
echo "    Username: ${PARSE_DASHBOARD_USER_ID}"
echo "    Password: ${PARSE_DASHBOARD_USER_PASSWORD}"
echo ""
echo "  SSH Access:"
echo "    ssh azureuser@${VM_FQDN}"
echo ""
echo "=========================================="
echo ""
echo "Useful commands:"
echo "  View logs:    ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml logs -f'"
echo "  Restart:      ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml restart'"
echo "  Stop:         ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml down'"
echo "  Start:        ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml up -d'"
echo "=========================================="
