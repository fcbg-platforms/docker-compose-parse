# Troubleshooting Guide

## Common Issues

### Issue 1: Parse Dashboard 403 Unauthorized Error

**Symptom:**

```text
error: Request using master key rejected as the request IP address 'X.X.X.X'
is not set in Parse Server option 'masterKeyIps'.
```

**Cause:** Parse Server's `PARSE_SERVER_MASTER_KEY_IPS` setting restricts which IP addresses can use the master key. By default, it only allows `localhost`.

**Solution:** Set `PARSE_SERVER_MASTER_KEY_IPS` in your [.env](.env) file:

```bash
# For development/testing (allows all IPs)
PARSE_SERVER_MASTER_KEY_IPS=0.0.0.0/0,::/0

# For production (restrict to specific IPs)
PARSE_SERVER_MASTER_KEY_IPS=1.2.3.4,5.6.7.8
```

Then restart the services:

```bash
# For VM deployment
ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml restart parse-server'

# For local development
docker compose restart parse-server
```

---

### Issue 2: MongoDB Password URL Encoding

**Symptom:** MongoDB connection errors with special characters in password.

**Cause:** Special characters in passwords (like `/`, `@`, `:`) must be URL-encoded in connection strings.

**Solution:** The [deploy-to-vm.sh](deploy-to-vm.sh) script automatically handles URL encoding. If manually setting `PARSE_SERVER_DATABASE_URI`, use proper encoding:

- `/` becomes `%2F`
- `@` becomes `%40`
- `:` becomes `%3A`

---

### Issue 3: Container Health Checks Failing

**Symptom:** Containers show as unhealthy in `docker compose ps`.

**Cause:** Health check commands require tools available in the container.

**Solution:** The [docker-compose.production.yml](docker-compose.production.yml) uses Node.js built-in modules for health checks instead of external tools like `wget`.

---

### Issue 4: CosmosDB Compatibility (Historical)

**Note:** This project previously used Azure Cosmos DB but migrated to MongoDB container due to compatibility issues.

**Issues encountered:**

- Cosmos DB MongoDB API 3.6 incompatible with Parse Server 8.x (requires wire version 8+)
- Missing collation support for case-insensitive indexes
- Azure ACI firewall blocking due to dynamic outbound IPs

**Conclusion:** Use MongoDB container on VM for full compatibility and persistent storage. See [archive/debug-docs/](archive/debug-docs/) for detailed historical context.

---

## Diagnostic Commands

### Check VM and Container Status

```bash
# SSH to VM
ssh azureuser@${VM_FQDN}

# Check container status
cd ~/parse-server && docker compose -f docker-compose.production.yml ps

# View logs
docker compose -f docker-compose.production.yml logs -f

# Check specific service logs
docker compose -f docker-compose.production.yml logs parse-server
docker compose -f docker-compose.production.yml logs mongodb
docker compose -f docker-compose.production.yml logs parse-dashboard
```

### Test Parse Server Health

```bash
# Test health endpoint
curl http://${VM_FQDN}:1337/parse/health

# Expected response
{"status":"ok"}
```

### Check MongoDB Connection

```bash
# Enter MongoDB container
ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml exec mongodb mongosh -u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin'

# List databases
show dbs

# Use Parse database
use parse

# List collections
show collections
```

### Azure Resource Management

```bash
# View VM status
az vm show --name ${VM_NAME} --resource-group ${RESOURCE_GROUP_NAME} --output table

# View VM public IP
az network public-ip show --name ${VM_NAME}-ip --resource-group ${RESOURCE_GROUP_NAME}

# Start/stop VM
az vm start --name ${VM_NAME} --resource-group ${RESOURCE_GROUP_NAME}
az vm stop --name ${VM_NAME} --resource-group ${RESOURCE_GROUP_NAME}
```

---

## Quick Fixes

### Restart Services

```bash
# Restart all services
ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml restart'

# Restart specific service
ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml restart parse-server'
```

### Redeploy Stack

```bash
# Full redeployment (from local machine)
./deploy-to-vm.sh
```

### View Disk Usage

```bash
# Check data disk usage
ssh azureuser@${VM_FQDN} 'df -h /mnt/parse-data'

# Check MongoDB data size
ssh azureuser@${VM_FQDN} 'du -sh /mnt/parse-data/mongodb'
```

---

## Getting Help

For detailed technical information, see:

- [CLAUDE.md](CLAUDE.md) - Comprehensive technical documentation
- [README.md](README.md) - Quick start guide
- [archive/debug-docs/](archive/debug-docs/) - Historical troubleshooting context
