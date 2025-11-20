# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains deployment configurations for a Parse Server stack with three components:

- **Database**: MongoDB container (latest version)
- **Parse Server**: Application backend (parseplatform/parse-server:8.4.0)
- **Parse Dashboard**: Web-based admin interface (parseplatform/parse-dashboard:8.0.0)

The project supports two deployment targets:

1. **Local development** using Docker Compose with MongoDB container
2. **Azure VM production deployment** using Docker Compose on a single VM in Switzerland North region

## Environment Configuration

All deployments require a `.env` file. Use [.env.example](.env.example) as template:

```bash
cp .env.example .env
# Edit .env with your credentials
```

Critical variables:

**For Both Local and Production:**

- `MONGO_INITDB_ROOT_USERNAME` / `MONGO_INITDB_ROOT_PASSWORD`: MongoDB root credentials
- `PARSE_SERVER_APPLICATION_ID` / `PARSE_SERVER_MASTER_KEY`: Parse Server authentication
- `PARSE_SERVER_DATABASE_NAME`: Database name (default: parse)
- `PARSE_DASHBOARD_USER_ID` / `PARSE_DASHBOARD_USER_PASSWORD`: Dashboard login credentials

**For Azure VM Production:**

- `RESOURCE_GROUP_NAME` / `AZURE_REGION`: Azure infrastructure settings (default: TikTik_Multi_2_RG / switzerlandnorth)
- `VM_NAME`: Azure VM name (default: parse-server-vm)
- `VM_SIZE`: VM size (default: Standard_B2s)
- `VM_DISK_SIZE`: Data disk size in GB (default: 32)
- `VM_DNS_LABEL`: DNS label for VM (default: parse-vm-prod)
- `VM_SSH_KEY_PATH`: Path to SSH public key (default: ~/.ssh/id_rsa.pub)

## Local Development

### Running the stack locally

```bash
# Start all services
docker compose up -d

# View logs
docker compose logs -f

# Stop services
docker compose down

# Stop and remove volumes (destroys data)
docker compose down -v
```

Services are available at:

- MongoDB: `localhost:27017`
- Parse Server: `http://localhost:1337/parse`
- Parse Dashboard: `http://localhost:4040`

### Local volume structure

Data persists in `./data/`:

- `./data/mongodb/`: MongoDB data files
- `./data/mongo-config/`: MongoDB configuration
- `./data/config-vol/`: Parse Server config

## Azure VM Deployment

### Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Bash shell (Git Bash, WSL, or Azure Cloud Shell)
- SSH key pair (default: `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`)
- `.env` file configured with Azure-specific variables

Make scripts executable once:

```bash
chmod +x deploy-*.sh setup-vm.sh cleanup-aci.sh
```

### Deployment Commands

**First-time VM setup (complete flow):**

```bash
# 1. Create Azure VM infrastructure (takes 3-5 minutes)
./deploy-vm.sh

# 2. Set up Docker and configure the VM (takes 2-3 minutes)
./setup-vm.sh

# 3. Deploy Parse Server stack to VM
./deploy-to-vm.sh
```

**Subsequent deployments (updates):**

```bash
# Deploy updated stack to existing VM
./deploy-to-vm.sh
```

**Clean up old ACI resources (if migrating):**

```bash
# Remove deprecated Azure Container Instances
./cleanup-aci.sh
```

### Deployment Architecture

The VM-based deployment uses a unified approach:

1. **Single VM**: Standard_B2s (2 vCPU, 4GB RAM) running Ubuntu 22.04
2. **Managed Disk**: 32GB Standard SSD attached at `/mnt/parse-data` for persistent storage
3. **Docker Compose**: All services run in containers on the VM with internal networking
4. **Public Access**: VM has a public IP with DNS label, ports 1337 and 4040 exposed
5. **Security**: SSH key authentication, Network Security Group with specific port rules

**Network Architecture:**

```text
Internet
    ↓
[VM Public IP: parse-vm-prod.switzerlandnorth.cloudapp.azure.com]
    ├── Port 22   → SSH access
    ├── Port 1337 → Parse Server
    └── Port 4040 → Parse Dashboard

VM Internal Network (Docker bridge):
    ├── mongodb:27017 (not exposed externally)
    ├── parse-server:1337
    └── parse-dashboard:4040
```

**Key script behaviors:**

- [deploy-vm.sh](deploy-vm.sh): Creates VM, networking, NSG rules, public IP with DNS, and managed disk
- [setup-vm.sh](setup-vm.sh): Installs Docker, formats/mounts data disk, creates systemd service for auto-start
- [deploy-to-vm.sh](deploy-to-vm.sh): Transfers files, configures environment, deploys Docker Compose stack
- [cleanup-aci.sh](cleanup-aci.sh): Removes deprecated ACI resources if migrating from old deployment

### Managing Azure VM Deployment

**VM and Container Management:**

```bash
# SSH into the VM
ssh azureuser@parse-vm-prod.switzerlandnorth.cloudapp.azure.com

# View container status
ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml ps'

# View logs
ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml logs -f'

# Restart services
ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml restart'

# Stop services
ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml down'

# Start services
ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml up -d'
```

**Azure Resource Management:**

```bash
# View VM status
az vm show --name ${VM_NAME} --resource-group ${RESOURCE_GROUP_NAME} --output table

# View VM public IP and FQDN
az network public-ip show --name ${VM_NAME}-ip --resource-group ${RESOURCE_GROUP_NAME}

# Start/stop VM (to save costs when not in use)
az vm start --name ${VM_NAME} --resource-group ${RESOURCE_GROUP_NAME}
az vm stop --name ${VM_NAME} --resource-group ${RESOURCE_GROUP_NAME}

# View NSG rules
az network nsg rule list --nsg-name ${VM_NAME}-nsg --resource-group ${RESOURCE_GROUP_NAME} --output table

# Delete entire VM and resources
az vm delete --name ${VM_NAME} --resource-group ${RESOURCE_GROUP_NAME} --yes

# Delete entire resource group (including all resources)
az group delete --name ${RESOURCE_GROUP_NAME} --yes --no-wait
```

## Key Technical Details

### Database Connection Strings

**VM Production (Internal Docker Network):**

```text
mongodb://username:password@mongodb:27017/database_name?authSource=admin
```

The container name `mongodb` is resolved via Docker's internal DNS. The database is NOT exposed to the internet for security.

**Local Development:**

```text
mongodb://username:password@mongodb:27017/database_name?authSource=admin
```

Same format as production. The `authSource=admin` parameter is critical for container authentication.

### Docker Compose Networking

All services communicate via the `parse-network` bridge network. Service names (`mongodb`, `parse-server`, `parse-dashboard`) resolve to container IPs within this network.

### Azure VM Production Specifics

**Virtual Machine:**

- Size: Standard_B2s (2 vCPU, 4GB RAM) - suitable for small-medium workloads
- OS: Ubuntu 22.04 LTS
- Authentication: SSH key-based (no password)
- Auto-start: Systemd service ensures Parse Server stack starts on boot

**Storage:**

- OS Disk: 30GB Standard SSD (managed by Azure)
- Data Disk: 32GB Standard SSD mounted at `/mnt/parse-data`
- MongoDB data persists across container restarts and VM reboots

**Networking:**

- Virtual Network: 10.0.0.0/16 with subnet 10.0.1.0/24
- Public IP: Static with DNS label
- NSG Rules: SSH (22), Parse Server (1337), Parse Dashboard (4040)
- MongoDB port 27017 NOT exposed externally

**Cost Estimate (Monthly, Switzerland North):**

- Standard_B2s VM: ~$38/month
- Standard SSD 32GB: ~$2.50/month
- Public IP: ~$3/month
- **Total: ~$43-45/month**

For comparison:

- Previous ACI deployment: ~$65-75/month without persistent storage
- VM deployment: ~40% cost savings with better reliability

### File Locations

**On Local Machine:**

- `docker-compose.yml`: Local development configuration
- `docker-compose.production.yml`: Production VM configuration
- `deploy-vm.sh`, `setup-vm.sh`, `deploy-to-vm.sh`: Deployment scripts
- `.env`: Environment configuration (not committed to git)

**On Azure VM:**

- `/home/azureuser/parse-server/`: Application directory
  - `docker-compose.production.yml`: Docker Compose configuration
  - `.env`: Environment variables (VM-specific)
- `/mnt/parse-data/`: Persistent data (managed disk)
  - `mongodb/`: MongoDB data files
  - `mongo-config/`: MongoDB configuration
  - `config-vol/`: Parse Server config

### Versions

- MongoDB: latest (8.x)
- Parse Server: 8.4.0
- Parse Dashboard: 8.0.0
- Docker Engine: Latest stable
- Docker Compose: Latest stable (v2.x plugin)

## Optional Features

The [docker-compose.yml](docker-compose.yml) includes a commented `mongo-restore` service for restoring MongoDB backups. To use:

1. Place backup files in `./mongo-backup/`
2. Uncomment the `mongo-restore` service
3. Adjust the database name and path as needed

## Migration History

### From ACI to VM (January 2025)

The project was migrated from Azure Container Instances (ACI) to VM-based deployment due to:

**ACI Issues:**

- No persistent storage for MongoDB (data lost on restarts)
- Complex networking with multiple public IPs
- Forced to use older Parse Server versions (5.5.0) due to Cosmos DB compatibility
- Higher costs (~$65-75/month)
- Management overhead with separate deployment scripts

**VM Benefits:**

- Persistent storage on managed disk
- Unified Docker Compose deployment (same as local dev)
- Can use latest Parse Server 8.4.0 and MongoDB 8.x
- Lower costs (~$43-45/month)
- Simpler management

**Legacy ACI scripts** are archived in [archive/aci-deployment/](archive/aci-deployment/) for reference.

### Previous Migrations

- **Parse Server**: 6.5.11 → 8.3.0 → 8.4.0
- **Parse Dashboard**: 7.5.0 → 8.0.0
- **Database**: MongoDB container → Cosmos DB → MongoDB container (VM)

The Cosmos DB approach was abandoned due to:

- Wire protocol version incompatibility with Parse Server
- Missing collation support for indexes
- ACI firewall issues with dynamic outbound IPs
- High costs for production use

## Security Considerations

### Production Recommendations

1. **Restrict SSH Access**: Update NSG to allow SSH only from your IP

   ```bash
   az network nsg rule update \
     --nsg-name ${VM_NAME}-nsg \
     --resource-group ${RESOURCE_GROUP_NAME} \
     --name Allow-SSH \
     --source-address-prefixes YOUR_IP_ADDRESS
   ```

2. **Restrict Master Key Access**: Set `PARSE_SERVER_MASTER_KEY_IPS` to specific IPs in production

3. **Enable HTTPS**: For production, consider:
   - Installing Let's Encrypt certificates with certbot
   - Using Azure Application Gateway for SSL termination
   - Setting `PARSE_DASHBOARD_ALLOW_INSECURE_HTTP=0`

4. **Regular Backups**: Implement automated MongoDB backups to Azure Blob Storage

5. **Monitoring**: Set up Azure Monitor alerts for:
   - VM CPU/memory usage
   - Disk space
   - Container health status

6. **Firewall**: Consider restricting Parse Server/Dashboard ports to specific IPs if not public-facing

## Troubleshooting

### VM Deployment Issues

**SSH Connection Fails:**

- Verify NSG allows SSH from your IP
- Check VM is running: `az vm show --name ${VM_NAME} --resource-group ${RESOURCE_GROUP_NAME}`
- Verify SSH key permissions: `chmod 600 ~/.ssh/id_rsa`

**Docker Containers Not Starting:**

- SSH to VM and check logs: `cd ~/parse-server && docker compose logs`
- Verify disk is mounted: `df -h /mnt/parse-data`
- Check Docker service: `sudo systemctl status docker`

**Parse Server Health Check Fails:**

- Check MongoDB is running: `docker compose ps mongodb`
- Verify DATABASE_URI is correct in `.env`
- Check container logs: `docker compose logs parse-server`

**Cannot Access Services from Internet:**

- Verify NSG rules: `az network nsg rule list --nsg-name ${VM_NAME}-nsg`
- Check containers are listening: `docker compose ps`
- Verify public IP: `az network public-ip show --name ${VM_NAME}-ip`

### Getting Help

For issues or questions:

1. Check container logs: `docker compose logs [service-name]`
2. Verify environment variables: `cat ~/parse-server/.env`
3. Review Azure resources: `az resource list --resource-group ${RESOURCE_GROUP_NAME}`
