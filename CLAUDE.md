# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains deployment configurations for a Parse Server stack with three components:

- **Database**: Azure Cosmos DB for MongoDB API (production) or MongoDB container (local dev)
- **Parse Server**: Application backend (parseplatform/parse-server:8.3.0)
- **Parse Dashboard**: Web-based admin interface (parseplatform/parse-dashboard:8.0.0)

The project supports two deployment targets:

1. **Local development** using Docker Compose with MongoDB container
2. **Azure production deployment** using Cosmos DB and Azure Container Instances (ACI) in Switzerland North region

## Environment Configuration

All deployments require a `.env` file. Use [.env.example](.env.example) as template:

```bash
cp .env.example .env
# Edit .env with your credentials
```

Critical variables:

**For Production (Azure Cosmos DB):**

- `COSMOS_DB_ACCOUNT_NAME`: Cosmos DB account name (e.g., parse-cosmos-12345)
- `PARSE_SERVER_DATABASE_URI`: Cosmos DB connection string (obtained from deploy-cosmosdb.sh)
- `PARSE_SERVER_APPLICATION_ID` / `PARSE_SERVER_MASTER_KEY`: Parse Server authentication
- `RESOURCE_GROUP_NAME` / `AZURE_REGION`: Azure infrastructure settings (default: TikTik_Multi_2_RG / switzerlandnorth)

**For Local Development (MongoDB Container):**

- `MONGO_INITDB_ROOT_USERNAME` / `MONGO_INITDB_ROOT_PASSWORD`: MongoDB root credentials
- `PARSE_SERVER_DATABASE_URI`: Built automatically for local docker-compose

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

**First-time setup:**

```bash
# 1. Create Cosmos DB (takes 2-5 minutes)
./deploy-cosmosdb.sh

# 2. Update .env file with the PARSE_SERVER_DATABASE_URI from output

# 3. Deploy Parse Server and Dashboard
./deploy-all.sh
```

**Subsequent deployments:**

```bash
# Deploy entire stack (Cosmos DB must already exist)
./deploy-all.sh

# Deploy individual components (for updates/fixes)
./deploy-cosmosdb.sh      # Create/verify Cosmos DB
./deploy-parse-server.sh  # Update Parse Server
./deploy-parse-dashboard.sh  # Update Dashboard
```

### Deployment architecture

The deployment scripts follow this pattern:

1. **Template-based deployment**: Each service has a YAML template (`*-deploy.yaml`) with placeholders (`__PLACEHOLDER__`)
2. **Runtime substitution**: Shell scripts use `sed` to replace placeholders with actual values from `.env`
3. **Temporary files**: Generated YAML files (`*-deploy-generated.yaml`) are created, deployed, then deleted
4. **DNS discovery**: Services query Azure for dependent service FQDNs to build connection strings

Key script behaviors:

- [deploy-cosmosdb.sh](deploy-cosmosdb.sh): Creates Azure Cosmos DB with MongoDB API (400 RU/s, ~$35/month), retrieves connection string
- [deploy-parse-server.sh](deploy-parse-server.sh): Detects Cosmos DB or MongoDB container, constructs appropriate `DATABASE_URI`
- [deploy-parse-dashboard.sh](deploy-parse-dashboard.sh): Discovers Parse Server FQDN, constructs dashboard connection URL
- [deploy-all.sh](deploy-all.sh): Orchestrates deployments - Cosmos DB check, then Parse Server and Dashboard with 20s wait

### Managing Azure deployments

```bash
# View deployed containers
az container list --resource-group ${RESOURCE_GROUP_NAME} --output table

# View Cosmos DB status
az cosmosdb show --name ${COSMOS_DB_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP_NAME}

# View logs
az container logs --name parse-server --resource-group ${RESOURCE_GROUP_NAME}
az container logs --name parse-dashboard --resource-group ${RESOURCE_GROUP_NAME}

# Get service endpoints
az container show --name parse-server --resource-group ${RESOURCE_GROUP_NAME} --query ipAddress.fqdn -o tsv
az container show --name parse-dashboard --resource-group ${RESOURCE_GROUP_NAME} --query ipAddress.fqdn -o tsv

# Monitor Cosmos DB metrics (RU consumption)
az monitor metrics list \
  --resource-type "Microsoft.DocumentDB/databaseAccounts" \
  --resource-group ${RESOURCE_GROUP_NAME} \
  --resource-name ${COSMOS_DB_ACCOUNT_NAME} \
  --metric "NormalizedRUConsumption"

# Delete entire deployment (including Cosmos DB)
az group delete --name ${RESOURCE_GROUP_NAME} --yes --no-wait
```

## Key Technical Details

### Database Connection Strings

**Cosmos DB for MongoDB API (Production):**

```text
mongodb://account-name:primary-key@account-name.mongo.cosmos.azure.com:10255/?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000&appName=ParseServer
```

Key differences from standard MongoDB:

- Port: `10255` (not 27017)
- SSL: `ssl=true` (mandatory)
- Special parameters: `replicaSet=globaldb&retrywrites=false`

**MongoDB Container (Local Development):**

```text
mongodb://username:password@hostname:27017/database_name?authSource=admin
```

The `authSource=admin` parameter is critical for container authentication.

### Docker Compose networking

All services communicate via the `parse-network` bridge network. Service names (`mongodb`, `parse-server`, `parse-dashboard`) resolve to container IPs within this network.

### Azure Production Deployment Specifics

**Cosmos DB:**

- Fully managed database service with 99.99% SLA
- Minimum throughput: 400 RU/s (~$35/month)
- Automatic backups (7-day retention included)
- Session consistency level (optimal for Parse Server)
- Supports autoscaling for production workloads

**Azure Container Instances:**

- All containers expose public IPs with DNS labels (`servicename-{random}.switzerlandnorth.azurecontainer.io`)
- Resource allocations: Parse Server (1 CPU, 1.5GB), Dashboard (0.5 CPU, 0.5GB)
- No TLS termination at container level; use Azure Application Gateway or Front Door for HTTPS

**Cost Estimate (Monthly):**

- Cosmos DB (400 RU/s): ~$35
- Parse Server ACI: ~$30
- Parse Dashboard ACI: ~$10
- **Total: ~$75/month** for production-ready managed infrastructure

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

- **Database**: Migrated from MongoDB container to Azure Cosmos DB for MongoDB API (production)
- MongoDB container archived (available in `archive/` for local development reference)
- Parse Server updated from 6.5.11 → 8.3.0 → 8.4.0 (local) / 8.3.0 (Azure)
- Parse Dashboard updated from 7.5.0 → 8.0.0
- Fixed CORS configuration with proper `PARSE_SERVER_ALLOW_HEADERS` and `PARSE_SERVER_ALLOW_CLIENT_CLASS_CREATION`
- Fixed `secureValue` issue in Azure deployments (changed to `value` for proper sed substitution)
- Auto-generate `PARSE_SERVER_URL` using Azure FQDN instead of localhost

## Migration from MongoDB Container to Cosmos DB

The MongoDB container deployment has been replaced with Azure Cosmos DB for production deployments due to:

- MongoDB 8.x incompatibility with Azure File Share permissions
- Frequent container crash/restart issues
- Need for managed database service with high availability

**Legacy MongoDB container files** are archived in `archive/` and remain available for local docker-compose development.

**For production**, use `./deploy-cosmosdb.sh` to create a fully managed Cosmos DB instance.
