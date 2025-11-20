# Cosmos DB MongoDB Version Compatibility Issue

## 🔍 Problem Identified

Your Parse Server crashes are caused by a **MongoDB wire protocol version mismatch**:

- **Your Cosmos DB**: MongoDB 3.6 API (wire version 6)
- **Parse Server 8.3.0 requires**: MongoDB 4.2+ (wire version 8+)

```text
Error: Server reports maximum wire version 6, but this version of the Node.js Driver requires at least 8 (MongoDB 4.2)
```

## ✅ Solution Options

### Option 1: Upgrade Cosmos DB (Recommended for Production)

Upgrade your Azure Cosmos DB to MongoDB 4.2+ API:

```bash
# 1. Check current Cosmos DB MongoDB version
az cosmosdb show \
  --name parse-cosmos-12345 \
  --resource-group TikTik_Multi_2_RG \
  --query "apiProperties.serverVersion" -o tsv

# 2. Upgrade to MongoDB 4.2
az cosmosdb mongodb upgrade-version \
  --account-name parse-cosmos-12345 \
  --resource-group TikTik_Multi_2_RG \
  --server-version "4.2"

# Or upgrade to MongoDB 5.0 (if available in your region)
az cosmosdb mongodb upgrade-version \
  --account-name parse-cosmos-12345 \
  --resource-group TikTik_Multi_2_RG \
  --server-version "5.0"
```

**Important Notes:**

- ⚠️ Upgrade is **one-way** (cannot downgrade)
- Takes 10-30 minutes typically
- No downtime required
- Backup your data first as a precaution

**After upgrade:**

- Use Parse Server 8.3.0 or 8.4.0
- All modern features available
- Better performance and compatibility

### Option 2: Downgrade Parse Server (Quick Fix)

Use Parse Server 5.5.0 which supports MongoDB 3.6:

**For diagnostic docker-compose (already updated):**

```yaml
parse-server:
  image: parseplatform/parse-server:5.5.0  # ✓ Compatible with MongoDB 3.6
```

**For Azure deployment:**

Update [parse-server-deploy.yaml](parse-server-deploy.yaml):

```yaml
containers:
  - name: parse-server
    properties:
      image: parseplatform/parse-server:5.5.0  # Change from 8.3.0
```

Then redeploy:

```bash
./deploy-parse-server.sh
```

**Limitations of Parse Server 5.x:**

- Missing newer features from 6.x, 7.x, 8.x
- Security updates may lag behind
- Not recommended for long-term production

## 🔍 Verify Cosmos DB Version

### Method 1: Azure Portal

1. Go to Azure Portal → Your Cosmos DB account
2. Look for "MongoDB server version" in Overview or Settings
3. Should show 3.6, 4.0, 4.2, 5.0, or 6.0

### Method 2: Azure CLI

```bash
az cosmosdb show \
  --name parse-cosmos-12345 \
  --resource-group TikTik_Multi_2_RG \
  --query "apiProperties.serverVersion" -o tsv
```

### Method 3: Connection Test

```bash
# Run the diagnostic stack
docker-compose -f docker-compose.diagnostic.yml up cosmos-db-test

# Check for wire version in logs
docker-compose -f docker-compose.diagnostic.yml logs cosmos-db-test | grep "wire version"
```

## 📊 Version Compatibility Matrix

| Cosmos DB MongoDB API | Parse Server Version | Status |
|----------------------|---------------------|--------|
| 3.2 | 4.x or earlier | ⚠️ Old, not recommended |
| 3.6 | 5.x | ✓ Compatible |
| 4.0 | 5.x - 7.x | ✓ Compatible |
| 4.2 | 5.x - 8.x | ✓ Compatible (recommended) |
| 5.0 | 6.x - 8.x | ✓✓ Best compatibility |
| 6.0 | 7.x - 8.x | ✓✓ Future-proof |

## 🚀 Testing the Fix

### Test with Parse Server 5.5.0 (Immediate)

```bash
# 1. Stop existing services
docker-compose -f docker-compose.diagnostic.yml down

# 2. Pull new image
docker-compose -f docker-compose.diagnostic.yml pull parse-server

# 3. Start services
docker-compose -f docker-compose.diagnostic.yml up

# 4. Verify Parse Server starts successfully
docker-compose -f docker-compose.diagnostic.yml logs parse-server

# 5. Test health endpoint
curl http://localhost:8080/parse/health
```

**Expected output:**

```json
{"status":"ok"}
```

### Test After Cosmos DB Upgrade

```bash
# 1. Wait for Cosmos DB upgrade to complete (10-30 min)

# 2. Update docker-compose.diagnostic.yml back to Parse Server 8.3.0
# Change line 22: image: parseplatform/parse-server:8.3.0

# 3. Test with upgraded Cosmos DB
docker-compose -f docker-compose.diagnostic.yml up

# 4. Verify no wire version errors
docker-compose -f docker-compose.diagnostic.yml logs parse-server
```

## 🔧 Apply Fix to Azure Production

### If Using Parse Server 5.5.0 (Quick Fix)

```bash
# 1. Update parse-server-deploy.yaml
sed -i 's/parseplatform\/parse-server:8.3.0/parseplatform\/parse-server:5.5.0/g' parse-server-deploy.yaml

# 2. Redeploy
./deploy-parse-server.sh

# 3. Verify
az container logs --name parse-server --resource-group TikTik_Multi_2_RG --tail 50
```

### If Upgrading Cosmos DB (Recommended)

```bash
# 1. Upgrade Cosmos DB
az cosmosdb mongodb upgrade-version \
  --account-name parse-cosmos-12345 \
  --resource-group TikTik_Multi_2_RG \
  --server-version "4.2"

# 2. Wait for upgrade completion
az cosmosdb show \
  --name parse-cosmos-12345 \
  --resource-group TikTik_Multi_2_RG \
  --query "apiProperties.serverVersion" -o tsv

# 3. Redeploy Parse Server (no changes needed, keep 8.3.0)
./deploy-parse-server.sh

# 4. Verify
az container logs --name parse-server --resource-group TikTik_Multi_2_RG
```

## 📝 Summary

**Root Cause:** Cosmos DB MongoDB 3.6 API incompatible with Parse Server 8.x

**Quick Fix:** Downgrade to Parse Server 5.5.0

- ✓ Works immediately
- ✓ No Cosmos DB changes
- ⚠️ Missing newer features

**Proper Fix:** Upgrade Cosmos DB to MongoDB 4.2+

- ✓ Use latest Parse Server 8.x
- ✓ Better performance
- ✓ Long-term solution
- ⚠️ One-way upgrade

## 🆘 Need More Help?

- [Parse Server Compatibility Docs](https://docs.parseplatform.org/parse-server/guide/#prerequisites)
- [Cosmos DB MongoDB Versions](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/feature-support-42)
- [DIAGNOSTIC-README.md](DIAGNOSTIC-README.md) - Full diagnostic guide
