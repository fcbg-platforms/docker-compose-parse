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
    az group create --name "${RESOURCE_GROUP_NAME}" --location "${AZURE_REGION}" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "⚠ Warning: Could not create resource group (may already exist or permissions issue)"
        # Check again if it exists despite the error
        if ! az group show --name "${RESOURCE_GROUP_NAME}" > /dev/null 2>&1; then
            echo "Failed to create resource group ${RESOURCE_GROUP_NAME}!"
            exit 1
        fi
    fi
fi
echo "✓ Resource group ready"

# Build the DATABASE_URI if not already set
if [ -z "$PARSE_SERVER_DATABASE_URI" ]; then
    # Check if using Cosmos DB or MongoDB container
    if [ -n "$COSMOS_DB_ACCOUNT_NAME" ]; then
        echo "Error: PARSE_SERVER_DATABASE_URI is not set."
        echo "Please run ./deploy-cosmosdb.sh first to create Cosmos DB and get the connection string."
        echo "Then update your .env file with the PARSE_SERVER_DATABASE_URI value."
        exit 1
    else
        # Fallback to MongoDB container (for local development)
        echo "⚠ Warning: Using MongoDB container mode (not recommended for production)"

        if [ -z "$MONGODB_DNS" ]; then
            echo "Getting MongoDB DNS..."
            MONGODB_DNS=$(az container show \
              --name mongodb \
              --resource-group "${RESOURCE_GROUP_NAME}" \
              --query ipAddress.fqdn \
              --output tsv 2>/dev/null)

            if [ -z "$MONGODB_DNS" ]; then
                echo "Error: MongoDB container not found and no Cosmos DB configured."
                echo "Please either:"
                echo "  1. Run ./deploy-cosmosdb.sh to set up Cosmos DB (recommended)"
                echo "  2. Run ./deploy-mongodb.sh to deploy MongoDB container"
                exit 1
            fi
        fi

        echo "MongoDB DNS: $MONGODB_DNS"
        PARSE_SERVER_DATABASE_URI="mongodb://${MONGO_INITDB_ROOT_USERNAME}:${MONGO_INITDB_ROOT_PASSWORD}@${MONGODB_DNS}:27017/${PARSE_SERVER_DATABASE_NAME}?authSource=admin"
    fi
else
    # DATABASE_URI is set, check if it's Cosmos DB or MongoDB
    if [[ "$PARSE_SERVER_DATABASE_URI" == *".mongo.cosmos.azure.com"* ]]; then
        echo "✓ Using Azure Cosmos DB for MongoDB API"
    else
        echo "✓ Using custom DATABASE_URI"
    fi
fi

# Generate a random identifier for the DNS label
RANDOM_ID=${RANDOM}

# Build PARSE_SERVER_URL for Azure (use the FQDN that will be created)
PARSE_SERVER_FQDN="parse-server-${RANDOM_ID}.${AZURE_REGION}.azurecontainer.io"
PARSE_SERVER_URL_AZURE="http://${PARSE_SERVER_FQDN}:1337/parse"

echo "Parse Server will be accessible at: $PARSE_SERVER_URL_AZURE"

# Create a temporary deployment file
TEMP_FILE="parse-server-deploy-generated.yaml"

# Escape special characters in DATABASE_URI for sed (& and \ need escaping)
DATABASE_URI_ESCAPED=$(echo "${PARSE_SERVER_DATABASE_URI}" | sed 's/[&/\]/\\&/g')

# Replace placeholders with actual values
sed "s|__APP_ID__|${PARSE_SERVER_APPLICATION_ID}|g" parse-server-deploy.yaml | \
sed "s|__MASTER_KEY__|${PARSE_SERVER_MASTER_KEY}|g" | \
sed "s|__DATABASE_URI__|${DATABASE_URI_ESCAPED}|g" | \
sed "s|__SERVER_URL__|${PARSE_SERVER_URL_AZURE}|g" | \
sed "s|__LOCATION__|${AZURE_REGION}|g" | \
sed "s|__RANDOM__|${RANDOM_ID}|g" > "$TEMP_FILE"

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
