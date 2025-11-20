#!/bin/bash

echo "=========================================="
echo "Parse Server Deployment Test Battery"
echo "=========================================="
echo ""

PARSE_SERVER_URL="http://parse-server-15374.switzerlandnorth.azurecontainer.io:1337/parse"
PARSE_DASHBOARD_URL="http://parse-dashboard-4049.switzerlandnorth.azurecontainer.io:4040"
MONGODB_URL="mongodb-12345.switzerlandnorth.azurecontainer.io"
APP_ID="myAppId"
MASTER_KEY="myMasterKey456"

# Test 1: Parse Server Health Check
echo "Test 1: Parse Server Health Check"
echo "-----------------------------------"
HEALTH=$(curl -s "${PARSE_SERVER_URL}/health")
if [ "$HEALTH" = '{"status":"ok"}' ]; then
    echo "✅ PASS: Parse Server is healthy"
else
    echo "❌ FAIL: Parse Server health check failed"
    echo "Response: $HEALTH"
fi
echo ""

# Test 2: Create a Test Object
echo "Test 2: Create Test Object"
echo "-----------------------------------"
CREATE_RESPONSE=$(curl -s -X POST \
  -H "X-Parse-Application-Id: ${APP_ID}" \
  -H "X-Parse-Master-Key: ${MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"testField":"testValue","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
  "${PARSE_SERVER_URL}/classes/TestObject")

if echo "$CREATE_RESPONSE" | grep -q "objectId"; then
    echo "✅ PASS: Object created successfully"
    OBJECT_ID=$(echo "$CREATE_RESPONSE" | grep -o '"objectId":"[^"]*"' | cut -d'"' -f4)
    echo "Object ID: $OBJECT_ID"
else
    echo "❌ FAIL: Failed to create object"
    echo "Response: $CREATE_RESPONSE"
fi
echo ""

# Test 3: Query Objects
echo "Test 3: Query Objects"
echo "-----------------------------------"
QUERY_RESPONSE=$(curl -s -X GET \
  -H "X-Parse-Application-Id: ${APP_ID}" \
  -H "X-Parse-Master-Key: ${MASTER_KEY}" \
  "${PARSE_SERVER_URL}/classes/TestObject")

if echo "$QUERY_RESPONSE" | grep -q "results"; then
    echo "✅ PASS: Query successful"
    RESULT_COUNT=$(echo "$QUERY_RESPONSE" | grep -o '"results":\[' | wc -l)
    echo "Results returned: $RESULT_COUNT"
else
    echo "❌ FAIL: Query failed"
    echo "Response: $QUERY_RESPONSE"
fi
echo ""

# Test 4: Update Object
if [ -n "$OBJECT_ID" ]; then
    echo "Test 4: Update Object"
    echo "-----------------------------------"
    UPDATE_RESPONSE=$(curl -s -X PUT \
      -H "X-Parse-Application-Id: ${APP_ID}" \
      -H "X-Parse-Master-Key: ${MASTER_KEY}" \
      -H "Content-Type: application/json" \
      -d '{"testField":"updatedValue"}' \
      "${PARSE_SERVER_URL}/classes/TestObject/${OBJECT_ID}")
    
    if echo "$UPDATE_RESPONSE" | grep -q "updatedAt"; then
        echo "✅ PASS: Object updated successfully"
    else
        echo "❌ FAIL: Update failed"
        echo "Response: $UPDATE_RESPONSE"
    fi
    echo ""
fi

# Test 5: Parse Dashboard Accessibility
echo "Test 5: Parse Dashboard Access"
echo "-----------------------------------"
DASHBOARD_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "${PARSE_DASHBOARD_URL}")
if [ "$DASHBOARD_RESPONSE" = "200" ]; then
    echo "✅ PASS: Dashboard is accessible"
    echo "Dashboard URL: ${PARSE_DASHBOARD_URL}"
else
    echo "❌ FAIL: Dashboard not accessible (HTTP $DASHBOARD_RESPONSE)"
fi
echo ""

# Test 6: MongoDB Connectivity
echo "Test 6: MongoDB Container Status"
echo "-----------------------------------"
MONGODB_STATUS=$(az container show --name mongodb-temp --resource-group TikTik_Multi_2_RG --query "containers[0].instanceView.currentState.state" -o tsv 2>/dev/null)
if [ "$MONGODB_STATUS" = "Running" ]; then
    echo "✅ PASS: MongoDB container is running"
    echo "MongoDB DNS: ${MONGODB_URL}"
else
    echo "❌ FAIL: MongoDB container not running (State: $MONGODB_STATUS)"
fi
echo ""

# Test 7: Parse Server Container Stability
echo "Test 7: Parse Server Stability Check"
echo "-----------------------------------"
PARSE_RESTART_COUNT=$(az container show --name parse-server --resource-group TikTik_Multi_2_RG --query "containers[0].instanceView.restartCount" -o tsv 2>/dev/null)
if [ "$PARSE_RESTART_COUNT" = "0" ]; then
    echo "✅ PASS: Parse Server has not restarted (stable)"
else
    echo "⚠️  WARNING: Parse Server has restarted $PARSE_RESTART_COUNT times"
fi
echo ""

# Test 8: CORS Headers
echo "Test 8: CORS Headers Check"
echo "-----------------------------------"
CORS_RESPONSE=$(curl -s -I -X OPTIONS \
  -H "Origin: http://example.com" \
  -H "Access-Control-Request-Method: POST" \
  "${PARSE_SERVER_URL}/classes/TestObject" | grep -i "access-control-allow-origin")

if echo "$CORS_RESPONSE" | grep -q "*"; then
    echo "✅ PASS: CORS headers configured correctly"
else
    echo "⚠️  WARNING: CORS headers may not be configured"
fi
echo ""

# Summary
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo ""
echo "Deployment URLs:"
echo "  Parse Server: ${PARSE_SERVER_URL}"
echo "  Parse Dashboard: ${PARSE_DASHBOARD_URL}"
echo "  MongoDB: ${MONGODB_URL}:27017"
echo ""
echo "Test battery completed!"
