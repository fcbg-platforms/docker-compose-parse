#!/bin/bash

# Load environment variables from .env file
set -a
source .env
set +a

# Set defaults if not provided
RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-TikTik_Multi_2_RG}
AZURE_REGION=${AZURE_REGION:-switzerlandnorth}
STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME:-tiktikstorage8040}

# Ensure the resource group exists
echo "Ensuring resource group ${RESOURCE_GROUP_NAME} exists..."
if ! az group show --name "${RESOURCE_GROUP_NAME}" > /dev/null 2>&1; then
    echo "Creating resource group ${RESOURCE_GROUP_NAME} in ${AZURE_REGION}..."
    az group create --name "${RESOURCE_GROUP_NAME}" --location "${AZURE_REGION}" > /dev/null
    if [ $? -ne 0 ]; then
        echo "Failed to create resource group ${RESOURCE_GROUP_NAME}!"
        exit 1
    fi
fi
echo "✓ Resource group ready"

# Check if storage account exists, create if not
echo "Checking if storage account exists..."
if ! az storage account show \
    --name "${STORAGE_ACCOUNT_NAME}" \
    --resource-group "${RESOURCE_GROUP_NAME}" \
    --query "name" \
    --output tsv > /dev/null 2>&1; then
    echo "Storage account not found. Creating storage account..."
    az storage account create \
      --name "${STORAGE_ACCOUNT_NAME}" \
      --resource-group "${RESOURCE_GROUP_NAME}" \
      --location "${AZURE_REGION}" \
      --sku Standard_LRS > /dev/null
    if [ $? -ne 0 ]; then
        echo "Failed to create storage account!"
        exit 1
    fi
    echo "✓ Storage account created"
else
    echo "✓ Storage account already exists"
fi

# Get storage account key
echo "Retrieving storage account key..."
STORAGE_KEY=$(az storage account keys list \
  --account-name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --query "[0].value" \
  --output tsv)

if [ -z "${STORAGE_KEY}" ]; then
    echo "Error: Failed to retrieve storage account key!"
    exit 1
fi
echo "✓ Storage key retrieved"

# Check if file share exists, create if not
echo "Checking if file share exists..."
SHARE_EXISTS=$(az storage share exists \
  --name mongodb-data \
  --account-name "${STORAGE_ACCOUNT_NAME}" \
  --account-key "${STORAGE_KEY}" \
  --query "exists" \
  --output tsv 2>/dev/null)

if [ "${SHARE_EXISTS}" != "true" ]; then
    echo "File share not found. Creating file share..."
    az storage share create \
      --name mongodb-data \
      --account-name "${STORAGE_ACCOUNT_NAME}" \
      --account-key "${STORAGE_KEY}" > /dev/null
    if [ $? -ne 0 ]; then
        echo "Failed to create file share!"
        exit 1
    fi
    echo "✓ File share created"
else
    echo "✓ File share already exists"
fi

# Create a temporary deployment file
TEMP_FILE="mongodb-deploy-generated.yaml"

# Replace placeholders with actual values
sed "s|__MONGO_USERNAME__|${MONGO_INITDB_ROOT_USERNAME}|g" mongodb-deploy.yaml | \
sed "s|__MONGO_PASSWORD__|${MONGO_INITDB_ROOT_PASSWORD}|g" | \
sed "s|__STORAGE_ACCOUNT__|${STORAGE_ACCOUNT_NAME}|g" | \
sed "s|__STORAGE_KEY__|${STORAGE_KEY}|g" | \
sed "s|__LOCATION__|${AZURE_REGION}|g" | \
sed "s|__RANDOM__|${RANDOM}|g" > "$TEMP_FILE"

# Deploy the container
echo "Deploying MongoDB container..."
az container create --resource-group "${RESOURCE_GROUP_NAME}" --file "$TEMP_FILE"

# Capture the result
RESULT=$?

# Clean up temporary file
rm -f "$TEMP_FILE"

if [ $RESULT -eq 0 ]; then
    echo "MongoDB deployment successful!"
    
    # Get MongoDB DNS name
    MONGODB_DNS=$(az container show \
      --name mongodb \
      --resource-group "${RESOURCE_GROUP_NAME}" \
      --query ipAddress.fqdn \
      --output tsv)
    
    echo "MongoDB DNS: $MONGODB_DNS"
else
    echo "MongoDB deployment failed!"
    exit 1
fi
