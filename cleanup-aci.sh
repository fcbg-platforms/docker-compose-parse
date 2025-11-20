#!/bin/bash
set -e

# Load environment variables
if [ ! -f .env ]; then
    echo "Error: .env file not found. Please create one from .env.example"
    exit 1
fi

source .env

echo "=========================================="
echo "Azure Container Instances Cleanup"
echo "=========================================="
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo ""
echo "This script will DELETE the following ACI resources:"
echo "  - Parse Server container (parse-server)"
echo "  - Parse Dashboard container (parse-dashboard)"
echo "  - MongoDB container (mongodb-*)"
echo "  - Azure Cosmos DB (if exists)"
echo ""
echo "WARNING: This action cannot be undone!"
echo "=========================================="
echo ""

# Confirmation prompt
read -p "Are you sure you want to proceed? Type 'yes' to continue: " confirmation

if [ "$confirmation" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup..."

# List all container instances in the resource group
echo ""
echo "Current ACI containers in resource group:"
az container list --resource-group "$RESOURCE_GROUP_NAME" --output table || true

# Delete Parse Server container
echo ""
echo "Deleting Parse Server container..."
if az container show --name parse-server --resource-group "$RESOURCE_GROUP_NAME" &> /dev/null; then
    az container delete \
        --name parse-server \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --yes
    echo "Parse Server container deleted"
else
    echo "Parse Server container not found (may already be deleted)"
fi

# Delete Parse Dashboard container
echo ""
echo "Deleting Parse Dashboard container..."
if az container show --name parse-dashboard --resource-group "$RESOURCE_GROUP_NAME" &> /dev/null; then
    az container delete \
        --name parse-dashboard \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --yes
    echo "Parse Dashboard container deleted"
else
    echo "Parse Dashboard container not found (may already be deleted)"
fi

# Delete MongoDB containers (search for any mongodb-* pattern)
echo ""
echo "Searching for MongoDB containers..."
MONGODB_CONTAINERS=$(az container list \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query "[?starts_with(name, 'mongodb')].name" \
    --output tsv) || true

if [ -n "$MONGODB_CONTAINERS" ]; then
    for container in $MONGODB_CONTAINERS; do
        echo "Deleting MongoDB container: $container"
        az container delete \
            --name "$container" \
            --resource-group "$RESOURCE_GROUP_NAME" \
            --yes
    done
    echo "MongoDB containers deleted"
else
    echo "No MongoDB containers found"
fi

# Check for and delete Cosmos DB if it exists
echo ""
echo "Checking for Azure Cosmos DB..."
if [ -n "${COSMOS_DB_ACCOUNT_NAME:-}" ]; then
    if az cosmosdb show --name "$COSMOS_DB_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" &> /dev/null; then
        echo ""
        echo "Found Cosmos DB account: $COSMOS_DB_ACCOUNT_NAME"
        read -p "Do you want to delete the Cosmos DB account? (yes/no): " cosmos_confirmation

        if [ "$cosmos_confirmation" = "yes" ]; then
            echo "Deleting Cosmos DB account (this may take a few minutes)..."
            az cosmosdb delete \
                --name "$COSMOS_DB_ACCOUNT_NAME" \
                --resource-group "$RESOURCE_GROUP_NAME" \
                --yes
            echo "Cosmos DB account deleted"
        else
            echo "Cosmos DB account preserved"
        fi
    else
        echo "No Cosmos DB account found with name: $COSMOS_DB_ACCOUNT_NAME"
    fi
else
    echo "No Cosmos DB account name configured in .env"
fi

# Final status check
echo ""
echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
echo ""
echo "Remaining ACI containers (if any):"
az container list --resource-group "$RESOURCE_GROUP_NAME" --output table || echo "No containers remaining"
echo ""
echo "Note: The resource group '$RESOURCE_GROUP_NAME' still exists."
echo "If you want to delete the entire resource group (including VM), run:"
echo "  az group delete --name $RESOURCE_GROUP_NAME --yes"
echo "=========================================="
