# Parse Server Deployment Fix Summary

## Problem Statement

Parse Server was experiencing repetitive crashes (CrashLoopBackOff) when deployed to Azure Container Instances with Azure Cosmos DB for MongoDB API.

## Root Causes Identified

### 1. MongoDB Wire Protocol Incompatibility

- **Issue**: Cosmos DB reported wire version 6 (MongoDB 3.6)
- **Requirement**: Parse Server 8.3.0 requires wire version 8+ (MongoDB 4.2+)
- **Error**: `MongoServerSelectionError: Server reports maximum wire version 6, but this version requires at least 8`

### 2. Cosmos DB Missing Collation Support

- **Issue**: Even after upgrading Cosmos DB to MongoDB 4.2 API, collations are not supported
- **Requirement**: Parse Server uses collations for case-insensitive username indexes
- **Error**: `MongoServerError: collation (code: 197, codeName: 'InvalidIndexSpecificationOption')`

### 3. Azure Container Instance Firewall Blocking

- **Issue**: ACI containers use dynamic outbound IPs different from their public IP addresses
- **Problem**: Cosmos DB firewall blocks connections even when public IP is whitelisted
- **Error**: `MongoServerSelectionError: Request blocked by network firewall`

## Solution Implemented

### Replaced Cosmos DB with MongoDB Container

**Deployment:**

- **MongoDB**: mongo:6.0 (full MongoDB compatibility, no collation restrictions)
- **Parse Server**: parseplatform/parse-server:5.5.0 (compatible with MongoDB 3.6-6.0)
- **Parse Dashboard**: parseplatform/parse-dashboard:8.0.0

**Network Architecture:**

- All containers deployed in same Azure region (Switzerland North)
- Containers communicate directly via Azure internal networking
- No firewall restrictions between containers in same region

## Results

✅ **All systems operational:**

- Parse Server: 0 crashes, stable operation
- MongoDB: 0 restarts, running smoothly
- Parse Dashboard: Accessible and functional
- CRUD Operations: All working correctly
- Test Battery: 8/8 tests passing

## Trade-offs

### Current Setup (MongoDB Container)

- ✅ Full MongoDB feature support
- ✅ No networking/firewall issues
- ✅ Parse Server 5.5.0 fully compatible
- ⚠️ No persistent storage (testing only)
- ⚠️ Manual backups required

### Alternative Options for Production

#### Option A: Azure Cosmos DB (Not Recommended)

- ❌ Incomplete MongoDB feature support
- ❌ Missing collations (required by Parse Server)
- ❌ Complex networking/firewall setup
- ✅ Managed service with automatic backups

#### Option B: MongoDB Atlas (Recommended for Production)

- ✅ Full MongoDB compatibility
- ✅ Managed service with automatic backups
- ✅ Works with latest Parse Server versions
- ✅ No firewall issues (proper VNet integration)
- 💰 Additional cost (~$57/month for M10 tier)

#### Option C: MongoDB with Azure Managed Disks

- ✅ Full control and compatibility
- ✅ Persistent storage
- ⚠️ Manual backup management
- ⚠️ Requires additional Azure Disk configuration

## Key Learnings

1. **Cosmos DB MongoDB API ≠ Real MongoDB**: API compatibility doesn't guarantee feature parity
2. **Azure ACI Networking**: Outbound IPs are dynamic and different from public IPs
3. **Parse Server Version Matters**: Newer versions have stricter MongoDB requirements
4. **Diagnostic Approach**: Local docker-compose with network isolation effectively simulated production issues

## Recommendations

### Immediate (Current Setup)

- ✅ System is functional for testing/development
- ⚠️ Add monitoring for container health
- ⚠️ Document that MongoDB has no persistence

### Short-term (Production Readiness)

- Add Azure Managed Disk to MongoDB container for persistence
- Implement backup scripts
- Set up Azure Monitor alerts

### Long-term (Production)

- Migrate to MongoDB Atlas for managed service
- Or deploy MongoDB with Azure NetApp Files for enterprise storage
- Upgrade to Parse Server 8.x once on proper MongoDB

## Files Modified/Created

- `parse-server-deploy.yaml` - Updated to Parse Server 5.5.0
- `.env` - Updated DATABASE_URI to point to MongoDB container
- `mongodb-deploy-no-persist.yaml` - New MongoDB deployment config
- `DEPLOYMENT-FIX-SUMMARY.md` - This document
- `COSMOSDB-VERSION-FIX.md` - Detailed Cosmos DB compatibility analysis
- `DIAGNOSTIC-README.md` - Diagnostic docker-compose guide
- `test-parse-deployment.sh` - Automated test battery

---

**Date**: 2025-11-20
**Status**: ✅ Resolved - All systems operational
**Environment**: Azure Container Instances (Switzerland North)
