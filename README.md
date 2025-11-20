# Parse Server Deployment

Production-ready Parse Server deployment using Docker Compose on Azure VM.

## Stack Components

- **MongoDB** (latest): Database with persistent storage
- **Parse Server** (8.4.0): Application backend
- **Parse Dashboard** (8.0.0): Web-based admin interface

## Quick Start

### Local Development

```bash
# 1. Create environment file
cp .env.example .env
# Edit .env with your credentials

# 2. Start services
docker compose up -d

# 3. Access services
# Parse Server: http://localhost:1337/parse
# Parse Dashboard: http://localhost:4040
```

### Azure VM Production Deployment

```bash
# Prerequisites:
# - Azure CLI installed and authenticated (az login)
# - SSH key pair (~/.ssh/id_rsa and ~/.ssh/id_rsa.pub)
# - Updated .env file with your configuration

# 1. Create VM infrastructure
./deploy-vm.sh

# 2. Set up Docker on VM
./setup-vm.sh

# 3. Deploy Parse Server stack
./deploy-to-vm.sh

# Access services at:
# Parse Server: http://parse-vm-prod.switzerlandnorth.cloudapp.azure.com:1337/parse
# Parse Dashboard: http://parse-vm-prod.switzerlandnorth.cloudapp.azure.com:4040
```

## Configuration

All configuration is managed through environment variables in `.env`. Copy `.env.example` to `.env` and update:

**Required Variables:**

- `MONGO_INITDB_ROOT_USERNAME`: MongoDB root username
- `MONGO_INITDB_ROOT_PASSWORD`: MongoDB root password
- `PARSE_SERVER_APPLICATION_ID`: Unique application ID
- `PARSE_SERVER_MASTER_KEY`: Master key (keep secret!)
- `PARSE_DASHBOARD_USER_ID`: Dashboard login username
- `PARSE_DASHBOARD_USER_PASSWORD`: Dashboard login password

**Azure VM Variables:**

- `VM_NAME`: Azure VM name (default: parse-server-vm)
- `VM_SIZE`: VM size (default: Standard_B2s)
- `VM_DNS_LABEL`: DNS label (default: parse-vm-prod)
- `RESOURCE_GROUP_NAME`: Azure resource group
- `AZURE_REGION`: Azure region (default: switzerlandnorth)

## Deployment Scripts

| Script | Purpose |
|--------|---------|
| `deploy-vm.sh` | Create Azure VM infrastructure (VNet, NSG, public IP, managed disk) |
| `setup-vm.sh` | Install Docker, mount data disk, configure auto-start |
| `deploy-to-vm.sh` | Deploy/update Parse Server stack on VM |
| `cleanup-aci.sh` | Remove old Azure Container Instances (if migrating) |
| `test-vm-deployment.sh` | Run comprehensive deployment tests |

## Architecture

### Local Development

```text
Your Machine
├── Docker Compose
│   ├── MongoDB (localhost:27017)
│   ├── Parse Server (localhost:1337)
│   └── Parse Dashboard (localhost:4040)
└── Data stored in ./data/
```

### Azure VM Production

```text
Azure VM (Standard_B2s)
├── Public IP: parse-vm-prod.switzerlandnorth.cloudapp.azure.com
├── Managed Disk: /mnt/parse-data (32GB SSD)
├── Docker Compose
│   ├── MongoDB (internal only)
│   ├── Parse Server (port 1337)
│   └── Parse Dashboard (port 4040)
└── Auto-start via systemd
```

## Management

### View Logs

```bash
# Local
docker compose logs -f

# Azure VM
ssh azureuser@parse-vm-prod.switzerlandnorth.cloudapp.azure.com
cd ~/parse-server && docker compose -f docker-compose.production.yml logs -f
```

### Restart Services

```bash
# Local
docker compose restart

# Azure VM
ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml restart'
```

### Update Deployment

```bash
# Local: just restart
docker compose down && docker compose up -d

# Azure VM: use deployment script
./deploy-to-vm.sh
```

## Cost Estimate (Azure)

**Monthly costs in Switzerland North region:**

- VM Standard_B2s (2 vCPU, 4GB RAM): ~$38
- Standard SSD 32GB: ~$2.50
- Public IP: ~$3
- **Total: ~$43-45/month**

## Security

### Production Recommendations

1. **Restrict SSH access to your IP:**

   ```bash
   az network nsg rule update \
     --nsg-name parse-server-vm-nsg \
     --resource-group TikTik_Multi_2_RG \
     --name Allow-SSH \
     --source-address-prefixes YOUR_IP_ADDRESS
   ```

2. **Set master key IP restrictions** in `.env`:

   ```bash
   PARSE_SERVER_MASTER_KEY_IPS=YOUR_IP_ADDRESS
   ```

3. **Enable HTTPS** (future enhancement):
   - Use Let's Encrypt with certbot
   - Or Azure Application Gateway for SSL termination

## Troubleshooting

For common issues and detailed solutions, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

Quick diagnostic test:

```bash
# Run comprehensive test suite
./test-vm-deployment.sh
```

Common issues:

- **Parse Dashboard 403 errors**: Set `PARSE_SERVER_MASTER_KEY_IPS=0.0.0.0/0,::/0` in `.env`
- **Containers not starting**: Check logs with `docker compose logs`
- **Cannot access from internet**: Verify NSG rules and container status

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed solutions.

## Migration from ACI

If you're migrating from Azure Container Instances:

1. Deploy new VM (follow Quick Start above)
2. Verify VM deployment works
3. Clean up old ACI resources:

   ```bash
   ./cleanup-aci.sh
   ```

Old ACI deployment scripts are archived in `archive/aci-deployment/`.

## Documentation

- [CLAUDE.md](CLAUDE.md) - Comprehensive technical documentation
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
- [.env.example](.env.example) - Configuration template
- [docker-compose.yml](docker-compose.yml) - Local development
- [docker-compose.production.yml](docker-compose.production.yml) - Production configuration
- [archive/](archive/) - Historical deployment files and debug documentation

## Version History

- **2025-01**: Migrated to VM-based deployment (from ACI)
- **2024**: Parse Server 8.4.0, Parse Dashboard 8.0.0
- **2024**: Previous ACI deployment with Cosmos DB (deprecated)

## License

This is a deployment configuration repository. Parse Server and its components have their own licenses.

## Support

For issues with:

- **Parse Server**: <https://github.com/parse-community/parse-server>
- **Parse Dashboard**: <https://github.com/parse-community/parse-dashboard>
- **This deployment**: Check logs and CLAUDE.md troubleshooting section
