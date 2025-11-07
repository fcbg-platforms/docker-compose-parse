# TikTik_Multi_2_RG: Parse Server Deployment Guide (Azure ACI)

This guide provides step-by-step instructions for deploying a **Parse Server**, **Parse Dashboard**, and **MongoDB** stack to **Azure Container Instances (ACI)** in the **Switzerland North** region.
The deployment includes **data restoration** from a MongoDB backup and uses a `.env` file for environment variables.

---

## **Prerequisites**

1. **Azure CLI** installed and logged in:

   ```bash
   az login
   ```

2. **`.env` file** with all required environment variables (e.g., `MONGO_INITDB_ROOT_USERNAME`, `PARSE_SERVER_APPLICATION_ID`).
3. **MongoDB backup** available (e.g., in a `.tar.gz` or `.dump` format).

---

## **Step 1: Create Resource Group**

Create a resource group in **Switzerland North**:

```bash
az group create --name TikTik_Multi_2_RG -l switzerlandnorth
```

---

## **Step 2: Load Environment Variables**

Load variables from your `.env` file into your shell:

```bash
set -a && source .env && set +a
```

Verify variables are loaded:

```bash
echo $MONGO_INITDB_ROOT_USERNAME
echo $PARSE_SERVER_APPLICATION_ID
```

---

## **Step 3: Create Azure File Share for MongoDB Persistence**

Since ACI doesn’t support persistent volumes, use **Azure Files** to store MongoDB data.

### **Create Storage Account**

```bash
az storage account create \
  --name tiktikstorage8040 \
  --resource-group TikTik_Multi_2_RG \
  --location switzerlandnorth \
  --sku Standard_LRS
```

### **Create File Share**

```bash
az storage share create \
  --name mongodb-data \
  --account-name tiktikstorage8040
```

### **Get Storage Account Key**

```bash
STORAGE_KEY=$(az storage account keys list \
  --account-name tiktikstorage8040 \
  --resource-group TikTik_Multi_2_RG \
  --query "[0].value" \
  --output tsv)
```

---

## **Step 4: Deploy MongoDB with Azure Files**

Deploy MongoDB with the Azure File Share mounted for data persistence:

```bash
az container create \
  --name mongodb \
  --resource-group TikTik_Multi_2_RG \
  --image mongo:8.2.1 \
  --environment-variables \
    "MONGO_INITDB_ROOT_USERNAME=$MONGO_INITDB_ROOT_USERNAME" \
    "MONGO_INITDB_ROOT_PASSWORD=$MONGO_INITDB_ROOT_PASSWORD" \
  --ports 27017 \
  --ip-address Public \
  --dns-name-label mongodb-$RANDOM \
  --restart-policy Always \
  --azure-file-volume-mount-path /data/db \
  --azure-file-volume-account-name tiktikstorage8040 \
  --azure-file-volume-account-key "$STORAGE_KEY" \
  --azure-file-volume-share-name mongodb-data
```

### **Get MongoDB DNS Name**

```bash
MONGODB_DNS=$(az container show \
  --name mongodb \
  --resource-group TikTik_Multi_2_RG \
  --query ipAddress.fqdn \
  --output tsv)
echo "MongoDB DNS: $MONGODB_DNS"
```

---

## **Step 5: Restore MongoDB Data**

Deploy a temporary ACI container to restore your MongoDB backup.
Upload your backup to a **publicly accessible URL** (e.g., Azure Blob Storage) or use a custom script.

### **Example: Restore from a Public URL**

```bash
az container create \
  --name mongo-restore \
  --resource-group TikTik_Multi_2_RG \
  --image mongo:7.0.3 \
  --command-line "bash -c 'sleep 20 && wget -O /backup.tar.gz https://your-backup-url/backup.tar.gz && tar -xzf /backup.tar.gz && mongorestore --host $MONGODB_DNS --port 27017 --username $MONGO_INITDB_ROOT_USERNAME --password $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin --db test --drop /backup'" \
  --environment-variables \
    MONGO_INITDB_ROOT_USERNAME=$MONGO_INITDB_ROOT_USERNAME \
    MONGO_INITDB_ROOT_PASSWORD=$MONGO_INITDB_ROOT_PASSWORD \
  --restart-policy OnFailure
```

---

## **Step 6: Deploy Parse Server**

Deploy Parse Server with the MongoDB connection string:

```bash
az container create \
  --name parse-server \
  --resource-group TikTik_Multi_2_RG \
  --image parseplatform/parse-server:8.3.0 \
  --environment-variables \
    PORT=1337 \
    PARSE_SERVER_APPLICATION_ID=$PARSE_SERVER_APPLICATION_ID \
    PARSE_SERVER_MASTER_KEY=$PARSE_SERVER_MASTER_KEY \
    PARSE_SERVER_DATABASE_URI="mongodb://${MONGO_INITDB_ROOT_USERNAME}:${MONGO_INITDB_ROOT_PASSWORD}@$MONGODB_DNS:27017/mycustomdb" \
    PARSE_SERVER_URL=$PARSE_SERVER_URL \
  --ports 1337 \
  --ip-address Public \
  --dns-name-label parse-server-$RANDOM \
  --restart-policy Always
```

### **Get Parse Server DNS Name**

```bash
PARSE_SERVER_DNS=$(az container show \
  --name parse-server \
  --resource-group TikTik_Multi_2_RG \
  --query ipAddress.fqdn \
  --output tsv)
echo "Parse Server DNS: $PARSE_SERVER_DNS"
```

---

## **Step 7: Deploy Parse Dashboard**

Deploy Parse Dashboard with the Parse Server URL:

```bash
az container create \
  --name parse-dashboard \
  --resource-group TikTik_Multi_2_RG \
  --image parseplatform/parse-dashboard:8.0.0 \
  --environment-variables \
    PARSE_DASHBOARD_SERVER_URL="http://$PARSE_SERVER_DNS:1337/parse" \
    PARSE_DASHBOARD_APP_ID=$PARSE_SERVER_APPLICATION_ID \
    PARSE_DASHBOARD_MASTER_KEY=$PARSE_SERVER_MASTER_KEY \
    PARSE_DASHBOARD_APP_NAME="$PARSE_DASHBOARD_APP_NAME" \
    PARSE_DASHBOARD_ALLOW_INSECURE_HTTP=$PARSE_DASHBOARD_ALLOW_INSECURE_HTTP \
    PARSE_DASHBOARD_USER_ID=$PARSE_DASHBOARD_USER_ID \
    PARSE_DASHBOARD_USER_PASSWORD=$PARSE_DASHBOARD_USER_PASSWORD \
  --ports 4040 \
  --ip-address Public \
  --dns-name-label parse-dashboard-$RANDOM \
  --restart-policy Always
```

### **Get Parse Dashboard DNS Name**

```bash
PARSE_DASHBOARD_DNS=$(az container show \
  --name parse-dashboard \
  --resource-group TikTik_Multi_2_RG \
  --query ipAddress.fqdn \
  --output tsv)
echo "Parse Dashboard DNS: $PARSE_DASHBOARD_DNS"
```

---

## **Step 8: Verify the Deployment**

1. **Access Parse Server**:

   ```
   http://$PARSE_SERVER_DNS:1337/parse
   ```

2. **Access Parse Dashboard**:

   ```
   http://$PARSE_DASHBOARD_DNS:4040
   ```

---

## **Step 9: Clean Up (Optional)**

To remove all resources when no longer needed:

```bash
az group delete --name TikTik_Multi_2_RG --yes --no-wait
```

---

## **Troubleshooting**

- **Check container logs**:

  ```bash
  az container logs --name mongodb --resource-group TikTik_Multi_2_RG
  az container logs --name parse-server --resource-group TikTik_Multi_2_RG
  az container logs --name parse-dashboard --resource-group TikTik_Multi_2_RG
  ```

- **Restart containers**:

  ```bash
  az container restart --name mongodb --resource-group TikTik_Multi_2_RG
  ```

---

## **Notes**

- **Data Persistence**: MongoDB data is stored in Azure Files. Ensure backups are taken regularly.
- **Security**: Restrict access to your containers using Azure Firewall or Network Security Groups (NSGs).
- **Cost Monitoring**: Use the Azure Pricing Calculator to estimate costs for your deployment.
