#!/bin/bash

# Load environment variables from .env file
set -a
source .env
set +a

# Get Parse Server DNS (should be set from previous deployment)
if [ -z "$PARSE_SERVER_DNS" ]; then
    echo "Getting Parse Server DNS..."
    PARSE_SERVER_DNS=$(az container show \
      --name parse-server \
      --resource-group TikTik_Multi_2_RG \
      --query ipAddress.fqdn \
      --output tsv)
    
    if [ -z "$PARSE_SERVER_DNS" ]; then
        echo "Error: Parse Server container not found. Please deploy Parse Server first."
        exit 1
    fi
fi

echo "Parse Server DNS: $PARSE_SERVER_DNS"

# Build the server URL for dashboard
DASHBOARD_SERVER_URL="http://${PARSE_SERVER_DNS}:1337/parse"

# Create a temporary deployment file
TEMP_FILE="parse-dashboard-deploy-generated.yaml"

# Replace placeholders with actual values
sed "s|__SERVER_URL__|${DASHBOARD_SERVER_URL}|g" parse-dashboard-deploy.yaml | \
sed "s|__APP_ID__|${PARSE_SERVER_APPLICATION_ID}|g" | \
sed "s|__MASTER_KEY__|${PARSE_SERVER_MASTER_KEY}|g" | \
sed "s|__APP_NAME__|${PARSE_DASHBOARD_APP_NAME}|g" | \
sed "s|__ALLOW_INSECURE__|${PARSE_DASHBOARD_ALLOW_INSECURE_HTTP}|g" | \
sed "s|__USER_ID__|${PARSE_DASHBOARD_USER_ID}|g" | \
sed "s|__USER_PASSWORD__|${PARSE_DASHBOARD_USER_PASSWORD}|g" | \
sed "s|__RANDOM__|${RANDOM}|g" > "$TEMP_FILE"

# Deploy the container
echo "Deploying Parse Dashboard container..."
az container create --resource-group TikTik_Multi_2_RG --file "$TEMP_FILE"

# Capture the result
RESULT=$?

# Clean up temporary file
rm -f "$TEMP_FILE"

if [ $RESULT -eq 0 ]; then
    echo "Parse Dashboard deployment successful!"
    
    # Get Parse Dashboard DNS name
    PARSE_DASHBOARD_DNS=$(az container show \
      --name parse-dashboard \
      --resource-group TikTik_Multi_2_RG \
      --query ipAddress.fqdn \
      --output tsv)
    
    echo "Parse Dashboard DNS: $PARSE_DASHBOARD_DNS"
    echo "Parse Dashboard URL: http://$PARSE_DASHBOARD_DNS:4040"
else
    echo "Parse Dashboard deployment failed!"
    exit 1
fi
