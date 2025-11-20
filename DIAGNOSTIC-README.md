# Parse Server Diagnostic Docker Compose

This diagnostic stack helps identify why Parse Server is crashing in Azure production by **mimicking the Azure deployment architecture locally** while connecting to the same remote Cosmos DB.

## 🎯 What This Diagnoses

- ✅ **Parse Server → Cosmos DB** connection issues
- ✅ **Parse Server startup crashes** with verbose logging
- ✅ **Dashboard → Parse Server** CORS/connectivity issues
- ✅ **Configuration mismatches** between local and Azure
- ✅ **Network isolation problems** (simulates Azure's separate container groups)

## 🏗️ Architecture Differences

### Production Azure Setup
```
Browser → Parse Dashboard (public IP)
              ↓ (HTTP over internet)
Parse Server (separate public IP) → Cosmos DB (port 10255)
```

### This Diagnostic Setup
```
Browser → Parse Dashboard (localhost:4040)
              ↓ (via nginx proxy - simulates external HTTP)
Parse Server (isolated network) → REMOTE Cosmos DB (port 10255)
```

**Key difference:** Services run in **separate Docker networks** and communicate through an nginx reverse proxy, mimicking Azure's isolated container groups where services have public IPs and communicate over HTTP (not internal Docker DNS).

## 📋 Prerequisites

1. **Azure Cosmos DB firewall access**
   ```bash
   # Add your local IP to Cosmos DB firewall
   az cosmosdb update \
     --name YOUR_COSMOS_ACCOUNT_NAME \
     --resource-group YOUR_RESOURCE_GROUP \
     --ip-range-filter "YOUR_LOCAL_PUBLIC_IP"

   # To find your public IP:
   curl -4 ifconfig.me
   ```

2. **Docker and Docker Compose installed**

3. **Production credentials** (from your `.env` file)

## 🚀 Quick Start

### Step 1: Configure Environment

```bash
# Copy the diagnostic environment template
cp .env.diagnostic .env.diagnostic.local

# Edit with your production values
nano .env.diagnostic.local
```

**Required values** (copy from your production `.env`):
- `PARSE_SERVER_DATABASE_URI` - Your Cosmos DB connection string
- `PARSE_SERVER_APPLICATION_ID` - Your app ID
- `PARSE_SERVER_MASTER_KEY` - Your master key
- `PARSE_DASHBOARD_APP_NAME` - Dashboard name
- `PARSE_DASHBOARD_USER_ID` - Dashboard username
- `PARSE_DASHBOARD_USER_PASSWORD` - Dashboard password

### Step 2: Run Diagnostic Stack

```bash
# Start all services with logs
docker-compose -f docker-compose.diagnostic.yml --env-file .env.diagnostic.local up

# Or run in background
docker-compose -f docker-compose.diagnostic.yml --env-file .env.diagnostic.local up -d
```

### Step 3: Check Service Status

```bash
# View all logs
docker-compose -f docker-compose.diagnostic.yml logs -f

# Check specific service logs
docker-compose -f docker-compose.diagnostic.yml logs -f parse-server
docker-compose -f docker-compose.diagnostic.yml logs -f parse-dashboard
docker-compose -f docker-compose.diagnostic.yml logs -f cosmos-db-test

# Check container status
docker-compose -f docker-compose.diagnostic.yml ps
```

## 🔍 Diagnostic Services

### 1. **cosmos-db-test** (Connection Test)
- **Purpose:** Tests Cosmos DB connectivity independently
- **Runs:** Once at startup, then exits
- **Success:** Shows "✓ SUCCESS: Connected to Cosmos DB"
- **Failure:** Shows connection errors with details

```bash
# View Cosmos DB test results
docker-compose -f docker-compose.diagnostic.yml logs cosmos-db-test
```

**If this fails:**
- Check firewall rules (your IP allowed in Cosmos DB)
- Verify connection string format
- Check Cosmos DB account status in Azure Portal

### 2. **parse-server** (Application Server)
- **Purpose:** Parse Server with verbose logging
- **Network:** Isolated (parse-server-network)
- **Configuration:** Matches Azure deployment exactly
- **Health check:** `/parse/health` endpoint

```bash
# Monitor Parse Server logs
docker-compose -f docker-compose.diagnostic.yml logs -f parse-server

# Check health status
curl http://localhost:8080/parse/health
```

**If this crashes:**
- Look for MongoDB connection errors in logs
- Check for "CrashLoopBackOff" pattern (immediate exits)
- Verify `PARSE_SERVER_DATABASE_URI` format
- Check for version compatibility issues

### 3. **nginx-proxy** (Reverse Proxy)
- **Purpose:** Simulates Azure external HTTP access
- **Port:** 8080 (maps to Parse Server's 1337)
- **CORS:** Configured to match Azure settings

```bash
# Test proxy access
curl http://localhost:8080/parse/health

# Check nginx logs
docker-compose -f docker-compose.diagnostic.yml logs -f nginx-proxy
```

### 4. **parse-dashboard** (Web Interface)
- **Purpose:** Admin dashboard
- **Network:** Isolated (proxy-network)
- **Access:** http://localhost:4040
- **Connection:** Via nginx proxy (not direct to Parse Server)

```bash
# Monitor Dashboard logs
docker-compose -f docker-compose.diagnostic.yml logs -f parse-dashboard

# Access dashboard
open http://localhost:4040
```

**If dashboard shows connection errors:**
- Check CORS errors in browser console
- Verify nginx proxy is running
- Ensure Parse Server is healthy

## 🩺 Diagnostic Workflow

### Scenario 1: Cosmos DB Connection Failure

**Symptoms:**
```
cosmos-db-test | ✗ FAILED: Cannot connect to Cosmos DB
parse-server    | Error: MongoNetworkError: connection timed out
```

**Solutions:**
1. Add your IP to Cosmos DB firewall:
   ```bash
   az cosmosdb update --name ACCOUNT --resource-group RG \
     --ip-range-filter "$(curl -4 ifconfig.me)"
   ```

2. Verify connection string format:
   ```
   mongodb://account:key@account.mongo.cosmos.azure.com:10255/parse?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000&appName=ParseServer
   ```

3. Check Cosmos DB status:
   ```bash
   az cosmosdb show --name ACCOUNT --resource-group RG --query provisioningState
   ```

### Scenario 2: Parse Server CrashLoopBackOff

**Symptoms:**
```
parse-server | [INFO] Parse Server starting...
parse-server exited with code 1
```

**Solutions:**
1. Check verbose logs for exact error:
   ```bash
   docker-compose -f docker-compose.diagnostic.yml logs parse-server | grep -i error
   ```

2. Test minimal configuration by removing optional env vars

3. Try adding connection string parameters:
   ```
   &directConnection=true&serverSelectionTimeoutMS=30000
   ```

4. Verify Parse Server version compatibility:
   ```bash
   docker run --rm parseplatform/parse-server:8.3.0 parse-server --version
   ```

### Scenario 3: Dashboard Connection/CORS Errors

**Symptoms:**
```
Browser console: CORS policy: No 'Access-Control-Allow-Origin' header
Dashboard: "Unable to connect to Parse Server"
```

**Solutions:**
1. Verify nginx proxy is running:
   ```bash
   curl http://localhost:8080/health
   ```

2. Check CORS headers:
   ```bash
   curl -H "Origin: http://localhost:4040" \
        -H "Access-Control-Request-Method: POST" \
        -X OPTIONS http://localhost:8080/parse
   ```

3. Ensure `PARSE_DASHBOARD_SERVER_URL` points to proxy:
   ```bash
   docker-compose -f docker-compose.diagnostic.yml exec parse-dashboard \
     env | grep PARSE_DASHBOARD_SERVER_URL
   # Should show: http://nginx-proxy:8080/parse
   ```

### Scenario 4: All Services Healthy Locally, Azure Still Crashes

**This indicates Azure-specific issues:**
1. **Resource limits** - Azure ACI may have insufficient CPU/memory
2. **Azure networking** - Firewall rules blocking Azure datacenter IPs
3. **DNS resolution** - FQDN issues in Azure
4. **Image caching** - Azure using outdated container image

**Check Azure resource allocation:**
```bash
az container show --name parse-server --resource-group RG \
  --query "containers[0].resources"
```

**Check Azure logs:**
```bash
az container logs --name parse-server --resource-group RG --tail 100
```

## 🧹 Cleanup

```bash
# Stop all services
docker-compose -f docker-compose.diagnostic.yml down

# Stop and remove volumes (if needed)
docker-compose -f docker-compose.diagnostic.yml down -v

# Remove networks
docker network rm diagnostic-parse-server-network diagnostic-proxy-network
```

## 📊 Success Criteria

✅ **All systems operational:**
```bash
$ docker-compose -f docker-compose.diagnostic.yml ps

NAME                      STATUS    PORTS
diagnostic-cosmos-test    Exited 0  # Should show "✓ SUCCESS" in logs
diagnostic-parse-server   Up        # Healthy
diagnostic-nginx-proxy    Up        0.0.0.0:8080->8080/tcp
diagnostic-parse-dashboard Up       0.0.0.0:4040->4040/tcp
```

✅ **Health check passes:**
```bash
$ curl http://localhost:8080/parse/health
{"status":"ok"}
```

✅ **Dashboard accessible:**
- Open http://localhost:4040
- Login with credentials
- See Parse Server connected

## 🔧 Advanced Diagnostics

### Test Parse Server API directly

```bash
# Create a test object
curl -X POST \
  -H "X-Parse-Application-Id: YOUR_APP_ID" \
  -H "X-Parse-Master-Key: YOUR_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"foo":"bar"}' \
  http://localhost:8080/parse/classes/TestObject

# Query objects
curl -X GET \
  -H "X-Parse-Application-Id: YOUR_APP_ID" \
  -H "X-Parse-Master-Key: YOUR_MASTER_KEY" \
  http://localhost:8080/parse/classes/TestObject
```

### Monitor network traffic

```bash
# Watch nginx access logs
docker-compose -f docker-compose.diagnostic.yml logs -f nginx-proxy | grep "GET\|POST"

# Inspect network connections
docker network inspect diagnostic-parse-server-network
docker network inspect diagnostic-proxy-network
```

### Interactive debugging

```bash
# Enter Parse Server container
docker-compose -f docker-compose.diagnostic.yml exec parse-server sh

# Test Cosmos DB from inside container
docker-compose -f docker-compose.diagnostic.yml exec parse-server sh -c \
  'wget -qO- http://localhost:1337/parse/health'
```

## 📝 Report Template

After running diagnostics, create an issue report with:

```markdown
## Environment
- Cosmos DB Account: [name]
- Azure Region: [region]
- Parse Server Version: 8.3.0
- Parse Dashboard Version: 8.0.0

## Cosmos DB Test Results
[Paste output from: docker-compose -f docker-compose.diagnostic.yml logs cosmos-db-test]

## Parse Server Logs
[Paste output from: docker-compose -f docker-compose.diagnostic.yml logs parse-server]

## Health Check
[Paste output from: curl http://localhost:8080/parse/health]

## Dashboard Status
- Accessible: [Yes/No]
- Can login: [Yes/No]
- Connection error: [error message if any]

## Observations
[What works locally vs. what fails in Azure]
```

## 🆘 Need Help?

1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for known issues
2. Review Azure deployment logs:
   ```bash
   az container logs --name parse-server --resource-group RG
   ```
3. Compare local vs Azure environment variables
4. Verify Cosmos DB MongoDB API version (must be 4.0+)

## 🔗 Related Files

- [docker-compose.diagnostic.yml](docker-compose.diagnostic.yml) - Diagnostic stack configuration
- [diagnostic-nginx.conf](diagnostic-nginx.conf) - Nginx reverse proxy config
- [.env.diagnostic](.env.diagnostic) - Environment template
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Known issues and solutions
- [CLAUDE.md](CLAUDE.md) - Full project documentation
