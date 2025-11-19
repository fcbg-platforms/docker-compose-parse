# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains deployment configurations for a Parse Server stack with three components:

- **MongoDB**: Database backend (mongo:8.2.1)
- **Parse Server**: Application backend (parseplatform/parse-server:8.3.0)
- **Parse Dashboard**: Web-based admin interface (parseplatform/parse-dashboard:8.0.0)

The project supports two deployment targets:

1. **Local development** using Docker Compose
2. **Azure Container Instances (ACI)** for production deployment in Switzerland North region

## Environment Configuration

All deployments require a `.env` file. Use [.env.example](.env.example) as template:

```bash
cp .env.example .env
# Edit .env with your credentials
```

Critical variables:

- `MONGO_INITDB_ROOT_USERNAME` / `MONGO_INITDB_ROOT_PASSWORD`: MongoDB root credentials
- `PARSE_SERVER_APPLICATION_ID` / `PARSE_SERVER_MASTER_KEY`: Parse Server authentication
- `PARSE_SERVER_DATABASE_URI`: Auto-generated for Azure deployments; manually set for local
- `RESOURCE_GROUP_NAME` / `AZURE_REGION`: Azure infrastructure settings (default: TikTik_Multi_2_RG / switzerlandnorth)
- `STORAGE_ACCOUNT_NAME`: Azure Storage for MongoDB persistence

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

## Azure Deployment

### Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Bash shell (Git Bash, WSL, or Azure Cloud Shell)
- `.env` file configured with Azure-specific variables

Make scripts executable once:

```bash
chmod +x deploy-*.sh
```

### Deployment commands

```bash
# Deploy entire stack (recommended)
./deploy-all.sh

# Deploy individual components (for updates/fixes)
./deploy-mongodb.sh
./deploy-parse-server.sh
./deploy-parse-dashboard.sh
```

### Deployment architecture

The deployment scripts follow this pattern:

1. **Template-based deployment**: Each service has a YAML template (`*-deploy.yaml`) with placeholders (`__PLACEHOLDER__`)
2. **Runtime substitution**: Shell scripts use `sed` to replace placeholders with actual values from `.env`
3. **Temporary files**: Generated YAML files (`*-deploy-generated.yaml`) are created, deployed, then deleted
4. **DNS discovery**: Each service queries Azure for the previous service's FQDN to build connection strings

Key script behaviors:

- [deploy-mongodb.sh](deploy-mongodb.sh): Creates Azure Storage account and file share, mounts as volume for MongoDB persistence
- [deploy-parse-server.sh](deploy-parse-server.sh): Discovers MongoDB FQDN, constructs `DATABASE_URI` with `authSource=admin` parameter
- [deploy-parse-dashboard.sh](deploy-parse-dashboard.sh): Discovers Parse Server FQDN, constructs dashboard connection URL
- [deploy-all.sh](deploy-all.sh): Orchestrates all three deployments with wait periods (30s for MongoDB, 20s for Parse Server)

### Managing Azure deployments

```bash
# View deployed containers
az container list --resource-group ${RESOURCE_GROUP_NAME} --output table

# View logs
az container logs --name mongodb --resource-group ${RESOURCE_GROUP_NAME}
az container logs --name parse-server --resource-group ${RESOURCE_GROUP_NAME}
az container logs --name parse-dashboard --resource-group ${RESOURCE_GROUP_NAME}

# Get service endpoints
az container show --name mongodb --resource-group ${RESOURCE_GROUP_NAME} --query ipAddress.fqdn -o tsv
az container show --name parse-server --resource-group ${RESOURCE_GROUP_NAME} --query ipAddress.fqdn -o tsv
az container show --name parse-dashboard --resource-group ${RESOURCE_GROUP_NAME} --query ipAddress.fqdn -o tsv

# Delete entire deployment
az group delete --name ${RESOURCE_GROUP_NAME} --yes --no-wait
```

## Key Technical Details

### MongoDB connection string format

The Parse Server connects to MongoDB using this URI pattern:

```text
mongodb://username:password@hostname:27017/database_name?authSource=admin
```

The `authSource=admin` parameter is critical for authentication to work correctly.

### Docker Compose networking

All services communicate via the `parse-network` bridge network. Service names (`mongodb`, `parse-server`, `parse-dashboard`) resolve to container IPs within this network.

### Azure ACI specifics

- All containers expose public IPs with DNS labels (`servicename-{random}.switzerlandnorth.azurecontainer.io`)
- MongoDB uses Azure File Share for data persistence across container restarts
- Resource allocations: MongoDB (1 CPU, 1.5GB), Parse Server (1 CPU, 1.5GB), Dashboard (0.5 CPU, 0.5GB)
- No TLS termination at container level; use Azure Application Gateway or Front Door for HTTPS

### Placeholder replacement pattern

When modifying deployment scripts, maintain the `__UPPERCASE_WITH_UNDERSCORES__` convention for placeholders in YAML templates. The `sed` chain in each script must match:

```bash
sed "s|__PLACEHOLDER__|${ENV_VAR}|g" template.yaml > generated.yaml
```

## Optional Features

The [docker-compose.yml](docker-compose.yml) includes a commented `mongo-restore` service for restoring MongoDB backups. To use:

1. Place backup files in `./mongo-backup/`
2. Uncomment the `mongo-restore` service
3. Adjust the database name and path as needed

## Version History Notes

Recent changes (from git history):

- MongoDB updated from 7.0.3 → 8.2.1
- Parse Server updated from 6.5.11 → 8.3.0 → 8.4.0 (local) / 8.3.0 (Azure)
- Parse Dashboard updated from 7.5.0 → 8.0.0
- Added `authSource=admin` parameter to MongoDB URI (critical for authentication)
- Refactored Azure deployment to use Azure Storage for MongoDB persistence
