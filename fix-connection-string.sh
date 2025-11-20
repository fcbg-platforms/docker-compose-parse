#!/bin/bash

# Get the connection string from Cosmos DB
COSMOS_CONNECTION_STRING=$(az cosmosdb keys list \
  --type connection-strings \
  --resource-group TikTik_Multi_2_RG \
  --name parse-cosmos-12345 \
  --query "connectionStrings[0].connectionString" \
  --output tsv)

# Remove existing appName parameter
BASE_CONNECTION=$(echo "${COSMOS_CONNECTION_STRING}" | sed 's/&appName=[^&]*//g')

# Insert database name '/parse' before the '?'
PARSE_SERVER_DATABASE_URI=$(echo "${BASE_CONNECTION}" | sed 's|\(.*\)/?|\1/parse?|')"&appName=ParseServer"

echo ""
echo "======================================"
echo "Corrected Connection String"
echo "======================================"
echo ""
echo "Add this to your .env file:"
echo ""
echo "PARSE_SERVER_DATABASE_URI=\"${PARSE_SERVER_DATABASE_URI}\""
echo ""
echo "======================================"
echo ""
