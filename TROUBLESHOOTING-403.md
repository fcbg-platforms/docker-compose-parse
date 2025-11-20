# Troubleshooting: Parse Dashboard 403 Unauthorized Error

## Problem

When accessing Parse Dashboard in your browser, you see a **403 Unauthorized** error.

## Root Cause

Parse Server's `PARSE_SERVER_MASTER_KEY_IPS` setting restricts which IP addresses can use the master key. By default, when this setting is empty or undefined, Parse Server only allows connections from `localhost` (127.0.0.1).

When Parse Dashboard tries to connect to Parse Server using the master key, the request comes from:

- Your browser's IP address (when accessing the dashboard)
- The Docker container's IP (internal requests)

These IPs are not `localhost` from Parse Server's perspective, so the requests are rejected with:

```
error: Request using master key rejected as the request IP address 'X.X.X.X'
is not set in Parse Server option 'masterKeyIps'.
```

## Solution

### Option 1: Allow All IPs (Development/Testing) ✅ APPLIED

Set `PARSE_SERVER_MASTER_KEY_IPS` to allow all IPv4 and IPv6 addresses:

```bash
PARSE_SERVER_MASTER_KEY_IPS=0.0.0.0/0,::/0
```

**This is what was applied to fix your deployment.**

### Option 2: Allow Specific IPs (Production - More Secure)

Restrict to specific IP addresses or ranges:

```bash
# Single IP
PARSE_SERVER_MASTER_KEY_IPS=1.2.3.4

# Multiple IPs (comma-separated)
PARSE_SERVER_MASTER_KEY_IPS=1.2.3.4,5.6.7.8

# CIDR range
PARSE_SERVER_MASTER_KEY_IPS=1.2.3.0/24
```

### Option 3: Allow Docker Network + Your IP

For VM deployments, you might want to allow:

- The Docker internal network (for Dashboard-to-Server communication)
- Your specific public IP (for browser access)

```bash
PARSE_SERVER_MASTER_KEY_IPS=172.18.0.0/16,YOUR_PUBLIC_IP
```

## How to Apply the Fix

### On VM Deployment

1. **SSH to the VM:**

   ```bash
   ssh azureuser@parse-vm-prod.switzerlandnorth.cloudapp.azure.com
   ```

2. **Edit the .env file:**

   ```bash
   cd ~/parse-server
   nano .env
   ```

3. **Update the line:**

   ```bash
   PARSE_SERVER_MASTER_KEY_IPS=0.0.0.0/0,::/0
   ```

4. **Restart Parse Server:**

   ```bash
   docker compose -f docker-compose.production.yml restart parse-server parse-dashboard
   ```

### On Local Development

1. **Edit `.env` in your project root**

2. **Update the line:**

   ```bash
   PARSE_SERVER_MASTER_KEY_IPS=0.0.0.0/0,::/0
   ```

3. **Restart containers:**

   ```bash
   docker compose restart parse-server parse-dashboard
   ```

## Verification

### 1. Check Parse Server Health

```bash
curl http://parse-vm-prod.switzerlandnorth.cloudapp.azure.com:1337/parse/health
```

Expected response:

```json
{"status":"ok"}
```

### 2. Check Parse Server Logs

```bash
ssh azureuser@parse-vm-prod.switzerlandnorth.cloudapp.azure.com \
  'cd ~/parse-server && docker compose -f docker-compose.production.yml logs parse-server --tail 50'
```

**Before fix** - you'll see:

```
error: Request using master key rejected as the request IP address 'X.X.X.X'
is not set in Parse Server option 'masterKeyIps'.
```

**After fix** - these errors should stop appearing.

### 3. Access Parse Dashboard

Open in browser:

```
http://parse-vm-prod.switzerlandnorth.cloudapp.azure.com:4040
```

You should now be able to:

- Log in with your credentials
- See your app in the dashboard
- Browse classes and data

## Security Considerations

### Development/Testing

✅ Using `0.0.0.0/0,::/0` is acceptable for:

- Local development
- Testing environments
- Internal networks behind firewalls
- When combined with other security measures (NSG rules, VPN)

### Production

⚠️ For production deployments, consider:

1. **Restrict to Known IPs:**

   ```bash
   PARSE_SERVER_MASTER_KEY_IPS=office_ip,admin_ip,ci_server_ip
   ```

2. **Use Azure Application Gateway or Front Door:**
   - Terminate SSL at the gateway
   - Restrict Parse Server to only accept requests from the gateway
   - Use gateway's IP in `masterKeyIps`

3. **Use VPN or Private Network:**
   - Deploy Parse Server in private subnet
   - Access via VPN only
   - Restrict `masterKeyIps` to VPN network range

4. **Additional Security Layers:**
   - Azure NSG rules to restrict source IPs at network level
   - Azure Firewall for advanced traffic filtering
   - Regular security audits and key rotation

## Updated Configuration

The `.env.example` file has been updated with the fix:

```bash
# Optional: IP addresses/CIDR ranges allowed to use master key
# For development/testing: "0.0.0.0/0,::/0" (allows all IPs)
# For production: restrict to specific IPs for security (e.g., "1.2.3.4,5.6.7.8")
# IMPORTANT: Default empty value restricts to localhost only, which blocks Parse Dashboard
PARSE_SERVER_MASTER_KEY_IPS=0.0.0.0/0,::/0
```

## Related Documentation

- [Parse Server Security Guide](https://docs.parseplatform.org/parse-server/guide/#security)
- [Master Key IPs Configuration](https://parseplatform.org/parse-server/api/master/ParseServerOptions.html)

## Status

✅ **FIXED** - Parse Dashboard now accessible without 403 errors

The VM deployment has been updated with `PARSE_SERVER_MASTER_KEY_IPS=0.0.0.0/0,::/0` and services have been restarted.
