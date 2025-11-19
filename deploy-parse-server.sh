#!/bin/bash

# Load environment variables from .env file
set -a
source .env
set +a

# Set defaults if not provided
RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-TikTik_Multi_2_RG}
AZURE_REGION=${AZURE_REGION:-switzerlandnorth}
PARSE_SERVER_DATABASE_NAME=${PARSE_SERVER_DATABASE_NAME:-parse}

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

# Get MongoDB DNS (should be set from previous deployment)
if [ -z "$MONGODB_DNS" ]; then
    echo "Getting MongoDB DNS..."
    MONGODB_DNS=$(az container show \
      --name mongodb \
      --resource-group "${RESOURCE_GROUP_NAME}" \
      --query ipAddress.fqdn \
      --output tsv)
    
    if [ -z "$MONGODB_DNS" ]; then
        echo "Error: MongoDB container not found. Please deploy MongoDB first."
        exit 1
    fi
fi

echo "MongoDB DNS: $MONGODB_DNS"

# Build the DATABASE_URI if not already set
if [ -z "$PARSE_SERVER_DATABASE_URI" ]; then
    PARSE_SERVER_DATABASE_URI="mongodb://${MONGO_INITDB_ROOT_USERNAME}:${MONGO_INITDB_ROOT_PASSWORD}@${MONGODB_DNS}:27017/${PARSE_SERVER_DATABASE_NAME}?authSource=admin"
fi

# Create a temporary deployment file
TEMP_FILE="parse-server-deploy-generated.yaml"

# Replace placeholders with actual values
sed "s|__APP_ID__|${PARSE_SERVER_APPLICATION_ID}|g" parse-server-deploy.yaml | \
sed "s|__MASTER_KEY__|${PARSE_SERVER_MASTER_KEY}|g" | \
sed "s|__DATABASE_URI__|${PARSE_SERVER_DATABASE_URI}|g" | \
sed "s|__SERVER_URL__|${PARSE_SERVER_URL}|g" | \
sed "s|__LOCATION__|${AZURE_REGION}|g" | \
sed "s|__RANDOM__|${RANDOM}|g" > "$TEMP_FILE"

# Deploy the container
echo "Deploying Parse Server container..."
az container create --resource-group "${RESOURCE_GROUP_NAME}" --file "$TEMP_FILE"

# Capture the result
RESULT=$?

# Clean up temporary file
rm -f "$TEMP_FILE"

if [ $RESULT -eq 0 ]; then
    echo "Parse Server deployment successful!"
    
    # Get Parse Server DNS name
        PARSE_SERVER_DNS=$(az container show \
            --name parse-server \
            --resource-group "${RESOURCE_GROUP_NAME}" \
            --query ipAddress.fqdn \
            --output tsv)
    
    echo "Parse Server DNS: $PARSE_SERVER_DNS"
    echo "Parse Server URL: http://$PARSE_SERVER_DNS:1337/parse"
else
    echo "Parse Server deployment failed!"
    exit 1
fi
