# Azure Container Instances (ACI) Deployment Scripts - ARCHIVED

This directory contains the deprecated Azure Container Instances (ACI) deployment scripts.

## Why Archived?

These scripts were used to deploy Parse Server components as individual Azure Container Instances. The deployment approach has been superseded by a VM-based Docker Compose solution due to:

1. **Storage Issues**: MongoDB containers in ACI had no persistent storage, leading to data loss on restarts
2. **Networking Complexity**: Required managing multiple public IPs and dynamic DNS discovery between services
3. **Version Constraints**: Forced to use older Parse Server versions (5.5.0) due to Cosmos DB compatibility issues
4. **Cost**: Multiple ACI instances (~$65-75/month) vs single VM (~$43-45/month)
5. **Management Overhead**: Separate deployment scripts and orchestration required

## Archived Files

- `deploy-all.sh` - Master orchestration script for ACI deployment
- `deploy-cosmosdb.sh` - Azure Cosmos DB creation script
- `deploy-parse-server.sh` - Parse Server ACI deployment
- `deploy-parse-dashboard.sh` - Parse Dashboard ACI deployment
- `parse-server-deploy.yaml` - Parse Server ACI template
- `parse-dashboard-deploy.yaml` - Parse Dashboard ACI template

## Current Deployment Method

See the main README.md and CLAUDE.md for VM-based deployment instructions using:

- `deploy-vm.sh` - Create Azure VM infrastructure
- `setup-vm.sh` - Configure VM with Docker
- `deploy-to-vm.sh` - Deploy Parse Server stack to VM
- `docker-compose.production.yml` - Production Docker Compose configuration

## Cleanup

To remove old ACI resources, use:

```bash
./cleanup-aci.sh
```

## Archived Date

2025-01-20
