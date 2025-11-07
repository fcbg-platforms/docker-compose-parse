#!/bin/bash

# Load environment variables from .env file
set -a
source .env
set +a

# Create a temporary deployment file
TEMP_FILE="mongodb-deploy-generated.yaml"

# Replace placeholders with actual values
sed "s|__MONGO_USERNAME__|${MONGO_INITDB_ROOT_USERNAME}|g" mongodb-deploy.yaml | \
sed "s|__MONGO_PASSWORD__|${MONGO_INITDB_ROOT_PASSWORD}|g" | \
sed "s|__STORAGE_ACCOUNT__|tiktikstorage8040|g" | \
sed "s|__STORAGE_KEY__|${STORAGE_KEY}|g" | \
sed "s|__RANDOM__|${RANDOM}|g" > "$TEMP_FILE"

# Deploy the container
echo "Deploying MongoDB container..."
az container create --resource-group TikTik_Multi_2_RG --file "$TEMP_FILE"

# Capture the result
RESULT=$?

# Clean up temporary file
rm -f "$TEMP_FILE"

if [ $RESULT -eq 0 ]; then
    echo "MongoDB deployment successful!"
    
    # Get MongoDB DNS name
    MONGODB_DNS=$(az container show \
      --name mongodb \
      --resource-group TikTik_Multi_2_RG \
      --query ipAddress.fqdn \
      --output tsv)
    
    echo "MongoDB DNS: $MONGODB_DNS"
else
    echo "MongoDB deployment failed!"
    exit 1
fi
