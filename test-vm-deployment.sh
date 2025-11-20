#!/bin/bash

# Test script for VM-based Parse Server deployment
# Tests connectivity, services, and functionality

set -a
source .env 2>/dev/null || echo "Warning: .env file not found"
set +a

VM_DNS_LABEL="${VM_DNS_LABEL:-parse-vm-prod}"
AZURE_REGION="${AZURE_REGION:-switzerlandnorth}"
VM_FQDN="${VM_DNS_LABEL}.${AZURE_REGION}.cloudapp.azure.com"

echo "======================================"
echo "Parse Server VM Deployment Tests"
echo "======================================"
echo "Testing VM: ${VM_FQDN}"
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

# Test 1: VM Accessibility
print_test "1. VM SSH Connectivity"
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no azureuser@${VM_FQDN} 'echo "SSH OK"' &>/dev/null; then
    print_pass "VM is accessible via SSH"
else
    print_fail "Cannot connect to VM via SSH"
fi

# Test 2: Docker Service Status
print_test "2. Docker Service Status"
DOCKER_STATUS=$(ssh azureuser@${VM_FQDN} 'sudo systemctl is-active docker' 2>/dev/null)
if [ "$DOCKER_STATUS" = "active" ]; then
    print_pass "Docker service is running"
else
    print_fail "Docker service is not active: $DOCKER_STATUS"
fi

# Test 3: Container Status
print_test "3. Container Status"
CONTAINER_STATUS=$(ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml ps --format json' 2>/dev/null)

if echo "$CONTAINER_STATUS" | grep -q "mongodb"; then
    MONGO_STATE=$(echo "$CONTAINER_STATUS" | jq -r 'select(.Service=="mongodb") | .State' 2>/dev/null || echo "unknown")
    if [ "$MONGO_STATE" = "running" ]; then
        print_pass "MongoDB container is running"
    else
        print_fail "MongoDB container state: $MONGO_STATE"
    fi
fi

if echo "$CONTAINER_STATUS" | grep -q "parse-server"; then
    SERVER_STATE=$(echo "$CONTAINER_STATUS" | jq -r 'select(.Service=="parse-server") | .State' 2>/dev/null || echo "unknown")
    if [ "$SERVER_STATE" = "running" ]; then
        print_pass "Parse Server container is running"
    else
        print_fail "Parse Server container state: $SERVER_STATE"
    fi
fi

if echo "$CONTAINER_STATUS" | grep -q "parse-dashboard"; then
    DASHBOARD_STATE=$(echo "$CONTAINER_STATUS" | jq -r 'select(.Service=="parse-dashboard") | .State' 2>/dev/null || echo "unknown")
    if [ "$DASHBOARD_STATE" = "running" ]; then
        print_pass "Parse Dashboard container is running"
    else
        print_fail "Parse Dashboard container state: $DASHBOARD_STATE"
    fi
fi

# Test 4: Data Disk Mount
print_test "4. Data Disk Mount Status"
DISK_MOUNT=$(ssh azureuser@${VM_FQDN} 'df -h /mnt/parse-data 2>/dev/null | tail -1')
if [ -n "$DISK_MOUNT" ]; then
    print_pass "Data disk is mounted at /mnt/parse-data"
    echo "  $DISK_MOUNT"
else
    print_fail "Data disk not mounted"
fi

# Test 5: Parse Server Health Endpoint
print_test "5. Parse Server Health Endpoint"
PARSE_SERVER_URL="http://${VM_FQDN}:1337/parse"
HEALTH_RESPONSE=$(curl -s "${PARSE_SERVER_URL}/health" 2>/dev/null)

if [ "$HEALTH_RESPONSE" = '{"status":"ok"}' ]; then
    print_pass "Parse Server health check successful"
else
    print_fail "Parse Server health check failed: $HEALTH_RESPONSE"
fi

# Test 6: Parse Server API Test (Create Object)
print_test "6. Parse Server API - Create Object"
if [ -n "$PARSE_SERVER_APPLICATION_ID" ] && [ -n "$PARSE_SERVER_MASTER_KEY" ]; then
    CREATE_RESPONSE=$(curl -s -X POST \
      -H "X-Parse-Application-Id: ${PARSE_SERVER_APPLICATION_ID}" \
      -H "X-Parse-Master-Key: ${PARSE_SERVER_MASTER_KEY}" \
      -H "Content-Type: application/json" \
      -d '{"testField":"testValue","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
      "${PARSE_SERVER_URL}/classes/TestObject" 2>/dev/null)

    if echo "$CREATE_RESPONSE" | grep -q "objectId"; then
        print_pass "Successfully created test object"
        OBJECT_ID=$(echo "$CREATE_RESPONSE" | grep -o '"objectId":"[^"]*"' | cut -d'"' -f4)
        echo "  Object ID: $OBJECT_ID"
    else
        print_fail "Failed to create test object"
        echo "  Response: ${CREATE_RESPONSE:0:200}"
    fi
else
    print_warn "Skipping - APP_ID or MASTER_KEY not set in .env"
fi

# Test 7: Parse Server API - Query Objects
print_test "7. Parse Server API - Query Objects"
if [ -n "$PARSE_SERVER_APPLICATION_ID" ] && [ -n "$PARSE_SERVER_MASTER_KEY" ]; then
    QUERY_RESPONSE=$(curl -s -X GET \
      -H "X-Parse-Application-Id: ${PARSE_SERVER_APPLICATION_ID}" \
      -H "X-Parse-Master-Key: ${PARSE_SERVER_MASTER_KEY}" \
      "${PARSE_SERVER_URL}/classes/TestObject" 2>/dev/null)

    if echo "$QUERY_RESPONSE" | grep -q "results"; then
        print_pass "Successfully queried objects"
        RESULT_COUNT=$(echo "$QUERY_RESPONSE" | grep -o '"objectId"' | wc -l)
        echo "  Objects found: $RESULT_COUNT"
    else
        print_fail "Failed to query objects"
    fi
else
    print_warn "Skipping - APP_ID or MASTER_KEY not set in .env"
fi

# Test 8: Parse Dashboard Accessibility
print_test "8. Parse Dashboard Accessibility"
PARSE_DASHBOARD_URL="http://${VM_FQDN}:4040"
DASHBOARD_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "${PARSE_DASHBOARD_URL}" 2>/dev/null)

if [ "$DASHBOARD_RESPONSE" = "200" ] || [ "$DASHBOARD_RESPONSE" = "302" ]; then
    print_pass "Parse Dashboard is accessible (HTTP $DASHBOARD_RESPONSE)"
else
    print_fail "Parse Dashboard not accessible (HTTP $DASHBOARD_RESPONSE)"
fi

# Test 9: CORS Headers
print_test "9. CORS Headers"
CORS_RESPONSE=$(curl -s -I -X OPTIONS \
  -H "Origin: http://example.com" \
  -H "Access-Control-Request-Method: POST" \
  "${PARSE_SERVER_URL}/classes/TestObject" 2>/dev/null | grep -i "access-control-allow-origin")

if echo "$CORS_RESPONSE" | grep -q "*"; then
    print_pass "CORS headers configured correctly"
else
    print_warn "CORS headers may not be configured"
fi

# Test 10: Container Logs Check
print_test "10. Container Logs Check"
PARSE_LOGS=$(ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml logs parse-server --tail 20' 2>/dev/null)

if echo "$PARSE_LOGS" | grep -qi "fatal\|critical\|crash"; then
    print_warn "Critical errors found in Parse Server logs"
    echo "$PARSE_LOGS" | grep -i "fatal\|critical\|crash" | head -3
elif echo "$PARSE_LOGS" | grep -qi "parse-server running"; then
    print_pass "Parse Server is running without critical errors"
else
    print_warn "Unable to verify Parse Server logs"
fi

# Test 11: Master Key IP Restriction
print_test "11. Master Key IP Configuration"
MASTER_KEY_IPS=$(ssh azureuser@${VM_FQDN} 'grep PARSE_SERVER_MASTER_KEY_IPS ~/parse-server/.env' 2>/dev/null | cut -d= -f2)

if [ "$MASTER_KEY_IPS" = "0.0.0.0/0,::/0" ]; then
    print_pass "Master Key IPs allow all (development mode)"
elif [ -n "$MASTER_KEY_IPS" ]; then
    print_pass "Master Key IPs restricted to: $MASTER_KEY_IPS"
else
    print_warn "Master Key IPs not configured (restricted to localhost)"
fi

# Test 12: Systemd Auto-start Configuration
print_test "12. Auto-start Configuration"
SYSTEMD_STATUS=$(ssh azureuser@${VM_FQDN} 'sudo systemctl is-enabled parse-stack.service' 2>/dev/null)

if [ "$SYSTEMD_STATUS" = "enabled" ]; then
    print_pass "Parse Server stack will auto-start on boot"
else
    print_warn "Auto-start not configured"
fi

# Test 13: Network Connectivity
print_test "13. Network Connectivity Test"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "${PARSE_SERVER_URL}/health" 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
    print_pass "Network connectivity is stable"
else
    print_fail "Network connectivity issues detected"
fi

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
else
    echo -e "${RED}Some tests failed. Please review the output above.${NC}"
    echo ""
    echo "Common fixes:"
    echo "1. Restart services: ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml restart'"
    echo "2. Check logs: ssh azureuser@${VM_FQDN} 'cd ~/parse-server && docker compose -f docker-compose.production.yml logs'"
    echo "3. Redeploy: ./deploy-to-vm.sh"
fi

echo ""
echo "======================================"
echo "Service URLs"
echo "======================================"
echo "Parse Server: ${PARSE_SERVER_URL}"
echo "Parse Dashboard: ${PARSE_DASHBOARD_URL}"
echo "SSH Access: ssh azureuser@${VM_FQDN}"
echo ""

# Cleanup test object if created
if [ -n "$OBJECT_ID" ]; then
    echo "Cleaning up test object..."
    curl -s -X DELETE \
      -H "X-Parse-Application-Id: ${PARSE_SERVER_APPLICATION_ID}" \
      -H "X-Parse-Master-Key: ${PARSE_SERVER_MASTER_KEY}" \
      "${PARSE_SERVER_URL}/classes/TestObject/${OBJECT_ID}" &>/dev/null
fi

exit $fail_count
