# Archive

This directory contains historical files from the Parse Server deployment project.

## Structure

### [aci-deployment/](aci-deployment/)

**Deprecated Azure Container Instances deployment scripts** (replaced by VM-based deployment).

These files were used when Parse Server was deployed as separate Azure Container Instances. The project migrated to a VM-based approach in January 2025 for:

- Better cost efficiency (~40% savings)
- Persistent storage for MongoDB
- Simplified management
- Full MongoDB feature compatibility

### [debug-docs/](debug-docs/)

**Historical troubleshooting documentation** from the migration process.

Contains detailed documentation of issues encountered during:

- CosmosDB compatibility problems (wire version, collation support, firewall)
- Azure Container Instance networking issues
- Parse Dashboard 403 authorization fixes
- Migration from ACI to VM deployment

Key documents:

- `COSMOSDB-VERSION-FIX.md` - CosmosDB MongoDB API version compatibility issues
- `FINAL-STATUS.md` - Complete deployment success report with all tests
- `DEPLOYMENT-SUCCESS.md` - Initial VM deployment summary
- `TROUBLESHOOTING-403.md` - Detailed guide for Parse Dashboard 403 errors
- `FINAL-FIX-SUMMARY.md` - Summary of all issues encountered and resolved

### [diagnostic-tools/](diagnostic-tools/)

**Debug and diagnostic tools** used during troubleshooting.

Contains:

- `docker-compose.diagnostic.yml` - Diagnostic stack that simulated Azure deployment locally
- `diagnostic-nginx.conf` - Nginx proxy config for testing external HTTP access
- `.env.diagnostic` - Environment template for diagnostic setup
- `DIAGNOSTIC-README.md` - Comprehensive guide for using diagnostic tools
- `deploy-mongodb-fixed.sh` - Earlier version of MongoDB deployment
- `fix-connection-string.sh` - One-time script for URL encoding fixes
- `mongodb-deploy-*.yaml` - ACI-specific MongoDB deployments
- `TikTik_Multi_2_RG_Deployment_Guide.md` - Early deployment documentation

## Current Deployment

For current deployment information, see the root directory:

- [../README.md](../README.md) - Quick start guide
- [../CLAUDE.md](../CLAUDE.md) - Comprehensive technical documentation
- [../TROUBLESHOOTING.md](../TROUBLESHOOTING.md) - Current troubleshooting guide

## Migration Summary

### Why We Migrated from ACI to VM

**Previous Setup (ACI):**

- 3 separate container instances (MongoDB, Parse Server, Dashboard)
- CosmosDB for MongoDB API (limited compatibility)
- Complex networking with multiple public IPs
- Cost: ~$65-75/month
- No persistent storage for MongoDB
- Parse Server 5.5.0 (older version due to CosmosDB constraints)

**Current Setup (VM):**

- Single VM (Standard_B2s) running Docker Compose
- MongoDB container with persistent managed disk
- Unified networking (Docker bridge)
- Cost: ~$43-45/month (40% savings)
- 32GB persistent SSD storage
- Parse Server 8.4.0 (latest version)

### Key Issues Resolved

1. **CosmosDB Compatibility**: MongoDB container provides full feature compatibility
2. **Firewall Issues**: VM with static IP eliminates ACI's dynamic outbound IP problems
3. **Storage Persistence**: Managed disk ensures data survives container restarts
4. **Cost Efficiency**: VM costs significantly less than multiple ACI instances
5. **Deployment Simplicity**: Same docker-compose config for local and production

## Historical Context

These archived files represent months of troubleshooting and optimization. They're preserved for:

- Understanding the project's evolution
- Learning from past issues
- Reference if similar problems arise
- Documenting the decision-making process

**Note**: These files are for reference only. Do not use them for current deployments.
