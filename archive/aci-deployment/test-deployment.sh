#!/bin/bash

# Test script for Parse Server deployment
# Tests connectivity, CORS, and service health

set -a
source .env 2>/dev/null || echo "Warning: .env file not found"
set +a

RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-TikTik_Multi_2_RG}

echo "======================================"
echo "Parse Server Deployment Tests"
echo "======================================"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass_count=0
fail_count=0

print_test() {
    echo ""
    echo "Test: $1"
    echo "----------------------------------------"
}

print_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((pass_count++))
}

print_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((fail_count++))
}

print_warn() {
    echo -e "${YELLOW}⚠ WARNING${NC}: $1"
}

# Test 1: Get Parse Server DNS
print_test "1. Retrieve Parse Server DNS"
PARSE_SERVER_DNS=$(az container show \
  --name parse-server \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --query ipAddress.fqdn \
  --output tsv 2>/dev/null)

if [ -n "$PARSE_SERVER_DNS" ]; then
    print_pass "Parse Server DNS: ${PARSE_SERVER_DNS}"
    PARSE_SERVER_URL="http://${PARSE_SERVER_DNS}:1337/parse"
else
    print_fail "Could not retrieve Parse Server DNS"
    exit 1
fi

# Test 2: Get Parse Dashboard DNS
print_test "2. Retrieve Parse Dashboard DNS"
PARSE_DASHBOARD_DNS=$(az container show \
  --name parse-dashboard \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --query ipAddress.fqdn \
  --output tsv 2>/dev/null)

if [ -n "$PARSE_DASHBOARD_DNS" ]; then
    print_pass "Parse Dashboard DNS: ${PARSE_DASHBOARD_DNS}"
    PARSE_DASHBOARD_URL="http://${PARSE_DASHBOARD_DNS}:4040"
else
    print_fail "Could not retrieve Parse Dashboard DNS"
fi

# Test 3: Check Parse Server container status
print_test "3. Check Parse Server Container Status"
PARSE_SERVER_STATE=$(az container show \
  --name parse-server \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --query "instanceView.state" \
  --output tsv 2>/dev/null)

if [ "$PARSE_SERVER_STATE" = "Running" ]; then
    print_pass "Parse Server container is Running"
else
    print_fail "Parse Server container state: ${PARSE_SERVER_STATE}"
fi

# Test 4: Check Parse Server logs for errors
print_test "4. Check Parse Server Logs"
PARSE_LOGS=$(az container logs --name parse-server --resource-group "${RESOURCE_GROUP_NAME}" --tail 20 2>/dev/null)

if echo "$PARSE_LOGS" | grep -qi "error\|failed\|exception"; then
    print_warn "Errors found in Parse Server logs"
    echo "$PARSE_LOGS" | grep -i "error\|failed\|exception" | head -5
else
    print_pass "No critical errors in Parse Server logs"
fi

# Test 5: Basic HTTP connectivity to Parse Server
print_test "5. HTTP Connectivity to Parse Server"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${PARSE_SERVER_URL}/health" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "404" ]; then
    print_pass "Parse Server is reachable (HTTP ${HTTP_CODE})"
else
    print_fail "Parse Server unreachable (HTTP ${HTTP_CODE})"
fi

# Test 6: Test /serverInfo endpoint (what Dashboard calls)
print_test "6. Test /serverInfo Endpoint"
echo "Testing: ${PARSE_SERVER_URL}/serverInfo"

SERVERINFO_RESPONSE=$(curl -s -w "\n%{http_code}" "${PARSE_SERVER_URL}/serverInfo" 2>&1)
SERVERINFO_HTTP_CODE=$(echo "$SERVERINFO_RESPONSE" | tail -1)
SERVERINFO_BODY=$(echo "$SERVERINFO_RESPONSE" | sed '$d')

echo "HTTP Status: ${SERVERINFO_HTTP_CODE}"
echo "Response: ${SERVERINFO_BODY:0:200}"

if [ "$SERVERINFO_HTTP_CODE" = "200" ]; then
    print_pass "/serverInfo endpoint is accessible"
else
    print_fail "/serverInfo returned HTTP ${SERVERINFO_HTTP_CODE}"
fi

# Test 7: Test CORS headers with OPTIONS request
print_test "7. Test CORS Preflight (OPTIONS)"
echo "Simulating browser CORS preflight request..."

CORS_RESPONSE=$(curl -s -i -X OPTIONS "${PARSE_SERVER_URL}/serverInfo" \
  -H "Origin: http://${PARSE_DASHBOARD_DNS}:4040" \
  -H "Access-Control-Request-Method: GET" \
  -H "Access-Control-Request-Headers: X-Parse-Application-Id" \
  2>&1)

echo "$CORS_RESPONSE" | head -20

if echo "$CORS_RESPONSE" | grep -qi "Access-Control-Allow-Origin"; then
    ALLOW_ORIGIN=$(echo "$CORS_RESPONSE" | grep -i "Access-Control-Allow-Origin" | cut -d: -f2- | tr -d '\r\n ')
    print_pass "CORS Access-Control-Allow-Origin: ${ALLOW_ORIGIN}"
else
    print_fail "No Access-Control-Allow-Origin header found"
fi

if echo "$CORS_RESPONSE" | grep -qi "Access-Control-Allow-Headers"; then
    print_pass "Access-Control-Allow-Headers header present"
else
    print_fail "No Access-Control-Allow-Headers header found"
fi

# Test 8: Test actual GET request with Origin header
print_test "8. Test Cross-Origin GET Request"
echo "Testing GET with Origin header..."

GET_RESPONSE=$(curl -s -i -X GET "${PARSE_SERVER_URL}/serverInfo" \
  -H "Origin: http://${PARSE_DASHBOARD_DNS}:4040" \
  2>&1)

echo "$GET_RESPONSE" | head -20

if echo "$GET_RESPONSE" | grep -qi "HTTP.*200"; then
    print_pass "GET request successful"
else
    print_fail "GET request failed"
fi

# Test 9: Check Parse Server environment variables
print_test "9. Verify Parse Server Configuration"
PARSE_ENV=$(az container show \
  --name parse-server \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --query "containers[0].environmentVariables" \
  --output json 2>/dev/null)

echo "$PARSE_ENV" | jq -r '.[] | select(.name | contains("ALLOW")) | "\(.name): \(.value)"' 2>/dev/null || \
echo "$PARSE_ENV" | grep -i "ALLOW"

ALLOW_ORIGIN=$(echo "$PARSE_ENV" | jq -r '.[] | select(.name=="PARSE_SERVER_ALLOW_ORIGIN") | .value' 2>/dev/null)
ALLOW_HEADERS=$(echo "$PARSE_ENV" | jq -r '.[] | select(.name=="PARSE_SERVER_ALLOW_HEADERS") | .value' 2>/dev/null)

if [ "$ALLOW_ORIGIN" = "*" ]; then
    print_pass "PARSE_SERVER_ALLOW_ORIGIN is set to '*'"
else
    print_fail "PARSE_SERVER_ALLOW_ORIGIN: ${ALLOW_ORIGIN}"
fi

if [ -n "$ALLOW_HEADERS" ]; then
    print_pass "PARSE_SERVER_ALLOW_HEADERS is configured"
    echo "  Headers: ${ALLOW_HEADERS:0:100}..."
else
    print_fail "PARSE_SERVER_ALLOW_HEADERS is not set"
fi

# Test 10: Check database connectivity
print_test "10. Check Database Connectivity"
DB_URI=$(echo "$PARSE_ENV" | jq -r '.[] | select(.name=="PARSE_SERVER_DATABASE_URI") | .value' 2>/dev/null)

if [[ "$DB_URI" == *".mongo.cosmos.azure.com"* ]]; then
    print_pass "Using Cosmos DB for MongoDB API"
    echo "  Connection: ${DB_URI:0:50}..."
elif [[ "$DB_URI" == mongodb://* ]]; then
    print_pass "MongoDB connection string configured"
    echo "  Connection: ${DB_URI:0:50}..."
else
    print_fail "Database URI not properly configured"
fi

# Test 11: Test from Dashboard perspective
print_test "11. Simulate Dashboard Connection"
echo "Testing what the Dashboard would call..."

DASHBOARD_TEST=$(curl -s -i -X GET "${PARSE_SERVER_URL}/serverInfo" \
  -H "Origin: ${PARSE_DASHBOARD_URL}" \
  -H "X-Parse-Application-Id: ${PARSE_SERVER_APPLICATION_ID}" \
  2>&1)

echo "$DASHBOARD_TEST" | head -25

if echo "$DASHBOARD_TEST" | grep -qi "HTTP.*200"; then
    print_pass "Dashboard-style request successful"
else
    print_fail "Dashboard-style request failed"
fi

# Test 12: Check for connection resets
print_test "12. Connection Stability Test"
echo "Testing for connection resets..."

for i in {1..3}; do
    RESET_TEST=$(curl -s -w "\nHTTP_CODE:%{http_code}\nTIME:%{time_total}" "${PARSE_SERVER_URL}/serverInfo" 2>&1)

    if echo "$RESET_TEST" | grep -qi "Connection reset\|recv failure"; then
        print_fail "Connection reset detected on attempt $i"
    elif echo "$RESET_TEST" | grep -q "HTTP_CODE:200"; then
        echo "  Attempt $i: Success"
    else
        echo "  Attempt $i: $(echo "$RESET_TEST" | grep HTTP_CODE)"
    fi
    sleep 1
done
print_pass "Connection stability test completed"

# Summary
echo ""
echo "======================================"
echo "Test Summary"
echo "======================================"
echo -e "${GREEN}Passed: ${pass_count}${NC}"
echo -e "${RED}Failed: ${fail_count}${NC}"
echo ""

if [ $fail_count -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    echo ""
    echo "If you're still experiencing CORS issues in the browser:"
    echo "1. Check browser console for specific error messages"
    echo "2. Verify the Dashboard URL matches: ${PARSE_DASHBOARD_URL}"
    echo "3. Try accessing Parse Dashboard directly and check Network tab"
    echo "4. Ensure you're not using HTTPS mixed with HTTP"
else
    echo -e "${RED}Some tests failed. Please review the output above.${NC}"
    echo ""
    echo "Common fixes:"
    echo "1. Redeploy Parse Server: ./deploy-parse-server.sh"
    echo "2. Check Parse Server logs: az container logs --name parse-server --resource-group ${RESOURCE_GROUP_NAME}"
    echo "3. Verify .env configuration"
fi

echo ""
echo "======================================"
echo "Service URLs"
echo "======================================"
echo "Parse Server: ${PARSE_SERVER_URL}"
echo "Parse Dashboard: ${PARSE_DASHBOARD_URL}"
echo ""

exit $fail_count
