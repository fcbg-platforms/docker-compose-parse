# Troubleshooting Guide

## Current Issue Summary

### Problem

Parse Server deployed to Azure Container Instances is experiencing a **CrashLoopBackOff** error when attempting to connect to Azure Cosmos DB for MongoDB API.

### Root Causes Identified

1. **`sed` Special Character Escaping Issue** ✅ FIXED
   - **Problem**: The Cosmos DB connection string contains `&` characters (e.g., `?ssl=true&replicaSet=globaldb`)
   - **Impact**: In `sed` replacement, `&` means "insert the matched pattern", so `&` was being replaced with `__DATABASE_URI__`
   - **Result**: Malformed connection string: `ssl=true__DATABASE_URI__replicaSet=globaldb__DATABASE_URI__...`
   - **Fix**: Added escaping in [deploy-parse-server.sh](deploy-parse-server.sh#L82-L83):

     ```bash
     DATABASE_URI_ESCAPED=$(echo "${PARSE_SERVER_DATABASE_URI}" | sed 's/[&/\]/\\&/g')
     ```

2. **Malformed Cosmos DB Connection String** ✅ FIXED
   - **Problem**: The [deploy-cosmosdb.sh](deploy-cosmosdb.sh) script was appending `&appName=ParseServer` to a connection string that already had `appName=@accountname@`
   - **Impact**: Duplicate and malformed `appName` parameters
   - **Fix**: Updated [deploy-cosmosdb.sh](deploy-cosmosdb.sh#L96-L104) to:
     - Remove existing `appName` parameter
     - Insert database name `/parse` before the `?`
     - Add clean `appName=ParseServer`

3. **Missing Database Name in Connection String** ✅ FIXED
   - **Problem**: Azure Cosmos DB connection string format: `mongodb://...@host:port/?params`
   - **Required**: `mongodb://...@host:port/DATABASE_NAME?params`
   - **Fix**: Connection string now includes `/parse` before query parameters

4. **Parse Server Still Crashing** ⚠️ IN PROGRESS
   - **Status**: Connection string is now correctly formatted
   - **Current Issue**: Parse Server exits immediately with no logs
   - **Next Steps**: Added verbose logging to diagnose Cosmos DB connection failure

### Correct Connection String Format

```text
mongodb://parse-cosmos-12345:KEY@parse-cosmos-12345.mongo.cosmos.azure.com:10255/parse?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000&appName=ParseServer
```

Key components:

- `/parse` - Database name (inserted before `?`)
- `?ssl=true` - SSL required for Cosmos DB
- `&replicaSet=globaldb` - Cosmos DB replica set
- `&retrywrites=false` - Cosmos DB doesn't support retry writes
- `&maxIdleTimeMS=120000` - Connection timeout
- `&appName=ParseServer` - Application identifier

### Test Script

Run the comprehensive test script to diagnose issues:

```bash
bash test-deployment.sh
```

This script tests:

1. DNS resolution
2. Container status
3. HTTP connectivity
4. CORS headers
5. Parse Server configuration
6. Database connectivity
7. Connection stability

### Common Commands

```bash
# Check Parse Server status
az container show --name parse-server --resource-group TikTik_Multi_2_RG --query "containers[0].instanceView.currentState"

# Check Parse Server logs
az container logs --name parse-server --resource-group TikTik_Multi_2_RG

# Check environment variables
az container show --name parse-server --resource-group TikTik_Multi_2_RG --query "containers[0].environmentVariables" -o json

# Delete and redeploy Parse Server
az container delete --name parse-server --resource-group TikTik_Multi_2_RG --yes
bash deploy-parse-server.sh

# Check Cosmos DB status
az cosmosdb show --name parse-cosmos-12345 --resource-group TikTik_Multi_2_RG
```

### Next Debugging Steps

1. **Enable Verbose Logging** ✅ DONE
   - Added `VERBOSE=1` and `PARSE_SERVER_LOG_LEVEL=verbose` to deployment
   - Redeploy to see detailed connection errors

2. **Verify Cosmos DB API Version**
   - Cosmos DB for MongoDB API supports versions 3.2, 3.6, 4.0, 4.2
   - Parse Server 8.3.0 requires MongoDB 4.0+
   - Check if API version mismatch exists

3. **Test Connection from Local Machine**
   - Use `mongosh` or Node.js script to test Cosmos DB connection
   - Verify credentials and connection string work outside Parse Server

4. **Check Parse Server Cosmos DB Compatibility**
   - Parse Server may have specific MongoDB driver requirements
   - Cosmos DB for MongoDB API may not support all features Parse Server needs
   - Consider adding `directConnection=true` parameter

### Potential Solutions

1. **Add Connection Options**
   Try adding these parameters to the connection string:

   ```bash
   &directConnection=true&serverSelectionTimeoutMS=30000
   ```

2. **Upgrade Cosmos DB API Version**
   Ensure Cosmos DB is using MongoDB API 4.0 or higher:

   ```bash
   az cosmosdb mongodb database show \
     --account-name parse-cosmos-12345 \
     --resource-group TikTik_Multi_2_RG \
     --name parse
   ```

3. **Test with Minimal Configuration**
   Deploy Parse Server with just required environment variables to isolate the issue

### Files Modified

- [deploy-parse-server.sh](deploy-parse-server.sh) - Fixed `sed` escaping
- [deploy-cosmosdb.sh](deploy-cosmosdb.sh) - Fixed connection string format
- [parse-server-deploy.yaml](parse-server-deploy.yaml) - Added verbose logging
- [.env](.env) - Corrected `PARSE_SERVER_DATABASE_URI`
- [test-deployment.sh](test-deployment.sh) - Created comprehensive test script

### Timeline

1. Initial CORS error reported
2. Discovered Parse Server was crashing (CrashLoopBackOff)
3. Fixed `sed` escaping issue with `&` characters
4. Fixed Cosmos DB connection string format (database name, appName)
5. Added verbose logging to diagnose remaining connection issue
6. **Current Status**: Parse Server still crashing - investigating Cosmos DB compatibility

### References

- [Parse Server Documentation](https://docs.parseplatform.org/parse-server/guide/)
- [Azure Cosmos DB MongoDB API](https://docs.microsoft.com/en-us/azure/cosmos-db/mongodb/introduction)
- [Parse Server Environment Variables](https://github.com/parse-community/parse-server#configuration)
