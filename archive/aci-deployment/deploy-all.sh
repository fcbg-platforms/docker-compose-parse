#!/bin/bash

# Master deployment script for Parse Server stack on Azure ACI
# This script deploys MongoDB, Parse Server, and Parse Dashboard in sequence

set -e  # Exit on any error

echo "======================================"
echo "Parse Server Stack Deployment to Azure"
echo "======================================"
echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo "Error: .env file not found!"
    echo "Please create a .env file with all required environment variables."
    exit 1
fi

# Load environment variables
echo "Loading environment variables from .env..."
set -a
source .env
set +a
echo "✓ Environment variables loaded"
echo ""

# Set defaults if not provided
RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-TikTik_Multi_2_RG}
AZURE_REGION=${AZURE_REGION:-switzerlandnorth}

# Ensure the resource group exists
echo "Ensuring resource group ${RESOURCE_GROUP_NAME} exists..."
if ! az group show --name "${RESOURCE_GROUP_NAME}" > /dev/null 2>&1; then
    echo "Creating resource group ${RESOURCE_GROUP_NAME} in ${AZURE_REGION}..."
    az group create --name "${RESOURCE_GROUP_NAME}" --location "${AZURE_REGION}" > /dev/null
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create resource group ${RESOURCE_GROUP_NAME}."
        exit 1
    fi
fi
echo "✓ Resource group ready"
echo ""

# Check if Azure CLI is logged in
echo "Checking Azure CLI authentication..."
az account show > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Not logged into Azure CLI. Please run 'az login' first."
    exit 1
fi
echo "✓ Azure CLI authenticated"
echo ""

# Deploy Database (Cosmos DB or MongoDB)
echo "======================================"
echo "Step 1: Deploying Database..."
echo "======================================"

# Check if using Cosmos DB or MongoDB container
if [ -n "$COSMOS_DB_ACCOUNT_NAME" ] && [ -z "$PARSE_SERVER_DATABASE_URI" ]; then
    echo "Deploying Azure Cosmos DB for MongoDB API..."
    bash deploy-cosmosdb.sh
    if [ $? -ne 0 ]; then
        echo "Cosmos DB deployment failed. Exiting."
        exit 1
    fi
    echo ""
    echo "⚠ IMPORTANT: Please update your .env file with the PARSE_SERVER_DATABASE_URI"
    echo "provided by deploy-cosmosdb.sh, then run this script again."
    exit 0
elif [[ "$PARSE_SERVER_DATABASE_URI" == *".mongo.cosmos.azure.com"* ]]; then
    echo "✓ Using existing Cosmos DB configuration"
    echo "  Connection: Cosmos DB for MongoDB API"
else
    echo "⚠ Using MongoDB container (not recommended for production)"
    bash deploy-mongodb.sh
    if [ $? -ne 0 ]; then
        echo "MongoDB deployment failed. Exiting."
        exit 1
    fi
    echo ""
    echo "Waiting 30 seconds for MongoDB to initialize..."
    sleep 30
fi
echo ""

# Deploy Parse Server
echo "======================================"
echo "Step 2: Deploying Parse Server..."
echo "======================================"
bash deploy-parse-server.sh
if [ $? -ne 0 ]; then
    echo "Parse Server deployment failed. Exiting."
    exit 1
fi
echo ""

# Wait for Parse Server to be ready
echo "Waiting 20 seconds for Parse Server to initialize..."
sleep 20
echo ""

# Deploy Parse Dashboard
echo "======================================"
echo "Step 3: Deploying Parse Dashboard..."
echo "======================================"
bash deploy-parse-dashboard.sh
if [ $? -ne 0 ]; then
    echo "Parse Dashboard deployment failed. Exiting."
    exit 1
fi
echo ""

# Summary
echo "======================================"
echo "Deployment Complete!"
echo "======================================"
echo ""
echo "Your Parse Server stack has been deployed successfully."
echo ""
echo "To view your containers:"
echo "  az container list --resource-group ${RESOURCE_GROUP_NAME} --output table"
echo ""
echo "To check logs:"
echo "  az container logs --name parse-server --resource-group ${RESOURCE_GROUP_NAME}"
echo "  az container logs --name parse-dashboard --resource-group ${RESOURCE_GROUP_NAME}"
echo ""
echo "To delete all resources:"
echo "  az group delete --name ${RESOURCE_GROUP_NAME} --yes --no-wait"
echo ""
