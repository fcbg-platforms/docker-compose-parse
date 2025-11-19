#!/bin/bash

# Load environment variables from .env file
set -a
source .env
set +a

# Set defaults if not provided
RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-TikTik_Multi_2_RG}
AZURE_REGION=${AZURE_REGION:-switzerlandnorth}
COSMOS_DB_ACCOUNT_NAME=${COSMOS_DB_ACCOUNT_NAME:-parse-cosmos-${RANDOM}}

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

echo "Checking Azure CLI authentication..."
if ! az account show > /dev/null 2>&1; then
    echo "Error: Not authenticated with Azure CLI. Please run 'az login' first."
    exit 1
fi
echo "✓ Azure CLI authenticated"

# Check if Cosmos DB account already exists
echo "Checking if Cosmos DB account exists..."
if az cosmosdb show --name "${COSMOS_DB_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP_NAME}" > /dev/null 2>&1; then
    echo "✓ Cosmos DB account '${COSMOS_DB_ACCOUNT_NAME}' already exists"
else
    echo "Creating Cosmos DB account with MongoDB API..."
    echo "  Account name: ${COSMOS_DB_ACCOUNT_NAME}"
    echo "  Region: ${AZURE_REGION}"
    echo "  Throughput: 400 RU/s (minimum, ~\$35/month)"
    echo ""
    echo "⏳ This may take 2-5 minutes..."

    az cosmosdb create \
      --resource-group "${RESOURCE_GROUP_NAME}" \
      --name "${COSMOS_DB_ACCOUNT_NAME}" \
      --kind MongoDB \
      --locations "regionName=${AZURE_REGION}" \
      --default-consistency-level "Session" \
      --enable-automatic-failover false \
      --output json > /dev/null

    if [ $? -ne 0 ]; then
        echo "Failed to create Cosmos DB account!"
        exit 1
    fi
    echo "✓ Cosmos DB account created successfully"
fi

# Create database with shared throughput
echo "Creating database 'parse' if it doesn't exist..."
if ! az cosmosdb mongodb database show \
    --account-name "${COSMOS_DB_ACCOUNT_NAME}" \
    --resource-group "${RESOURCE_GROUP_NAME}" \
    --name "parse" > /dev/null 2>&1; then

    az cosmosdb mongodb database create \
      --resource-group "${RESOURCE_GROUP_NAME}" \
      --account-name "${COSMOS_DB_ACCOUNT_NAME}" \
      --name "parse" \
      --throughput 400 > /dev/null

    if [ $? -eq 0 ]; then
        echo "✓ Database 'parse' created with 400 RU/s"
    else
        echo "⚠ Warning: Failed to create database (it may already exist)"
    fi
else
    echo "✓ Database 'parse' already exists"
fi

# Retrieve connection string
echo "Retrieving Cosmos DB connection string..."
COSMOS_CONNECTION_STRING=$(az cosmosdb keys list \
  --type connection-strings \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --name "${COSMOS_DB_ACCOUNT_NAME}" \
  --query "connectionStrings[0].connectionString" \
  --output tsv)

if [ -z "${COSMOS_CONNECTION_STRING}" ]; then
    echo "Error: Failed to retrieve connection string!"
    exit 1
fi

# Format the connection string for Parse Server
# Azure provides: mongodb://account:key@account.mongo.cosmos.azure.com:10255/?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000&appName=@account@
# We need to: 1) Remove the existing appName parameter, 2) Add database name before the ?, 3) Add our own appName

# Remove existing appName parameter and extract base connection
BASE_CONNECTION=$(echo "${COSMOS_CONNECTION_STRING}" | sed 's/&appName=[^&]*//g')

# Insert database name '/parse' before the '?'
PARSE_SERVER_DATABASE_URI=$(echo "${BASE_CONNECTION}" | sed 's|\(.*\)/?|\1/parse?|')&appName=ParseServer"

# Get the host for display
COSMOS_HOST=$(echo "${COSMOS_CONNECTION_STRING}" | sed -n 's/.*@\([^:]*\):.*/\1/p')

echo ""
echo "======================================"
echo "Cosmos DB Deployment Successful!"
echo "======================================"
echo ""
echo "Account Name: ${COSMOS_DB_ACCOUNT_NAME}"
echo "Host: ${COSMOS_HOST}"
echo "Database: parse"
echo "Throughput: 400 RU/s (~\$35/month)"
echo ""
echo "======================================"
echo "IMPORTANT: Update your .env file"
echo "======================================"
echo ""
echo "Add these lines to your .env file:"
echo ""
echo "# Cosmos DB Configuration"
echo "COSMOS_DB_ACCOUNT_NAME=${COSMOS_DB_ACCOUNT_NAME}"
echo "PARSE_SERVER_DATABASE_URI=\"${PARSE_SERVER_DATABASE_URI}\""
echo ""
echo "======================================"
echo ""
echo "Next steps:"
echo "1. Update your .env file with the above configuration"
echo "2. Run: ./deploy-parse-server.sh"
echo "3. Run: ./deploy-parse-dashboard.sh"
echo ""
echo "Or run all at once:"
echo "  ./deploy-all.sh"
echo ""
