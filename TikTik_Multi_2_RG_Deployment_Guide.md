# TikTik_Multi_2_RG: Parse Server Deployment Guide (Azure ACI)

This guide explains how to deploy MongoDB, Parse Server, and Parse Dashboard to **Azure Container Instances (ACI)** in **Switzerland North** using the helper scripts bundled with this project.

---

## Prerequisites

- Azure CLI installed and logged in: `az login`
- `.env` file beside the scripts (use `.env.example` as a template). At minimum set `MONGO_INITDB_ROOT_USERNAME`, `MONGO_INITDB_ROOT_PASSWORD`, `RESOURCE_GROUP_NAME`, and `AZURE_REGION` (defaults are provided).
- MongoDB backup reachable from Azure (optional if you plan to restore data)
- Bash shell (Git Bash, WSL, or Azure Cloud Shell)

Make the scripts executable once:

```bash
chmod +x deploy-*.sh
```

---

## Quick Deploy (recommended)

Run the master script; it orchestrates storage provisioning, MongoDB, Parse Server, and the dashboard:

```bash
./deploy-all.sh
```

The script will:

1. Load variables from `.env`
2. Ensure the Azure resource group exists (creates it if missing)
3. Ensure the storage account and file share exist
4. Deploy MongoDB and wait for a public FQDN
5. Deploy Parse Server (using the discovered MongoDB DNS)
6. Deploy Parse Dashboard (using the discovered Parse Server DNS)
7. Print the public endpoints at the end

Keep the terminal open until the script finishes.

---

## Deploy Components Individually (optional)

Use these if you need to redeploy a single service:

```bash
./deploy-mongodb.sh
./deploy-parse-server.sh
./deploy-parse-dashboard.sh
```

Each script reuses the `.env` variables and regenerates the required YAML on the fly.

---

## Accessing the Services

After deployment, copy the DNS names printed by the scripts:

- **Parse Server:** `http://parse-server-<random>.switzerlandnorth.azurecontainer.io:1337/parse`
- **Parse Dashboard:** `http://parse-dashboard-<random>.switzerlandnorth.azurecontainer.io:4040`

Use the credentials from your `.env` file to sign in to the dashboard.

### Retrieve DNS Names Later

If the terminal output was closed, query Azure for the endpoints:

```bash
RG=${RESOURCE_GROUP_NAME:-TikTik_Multi_2_RG}
az container show --name mongodb --resource-group "$RG" --query ipAddress.fqdn -o tsv
az container show --name parse-server --resource-group "$RG" --query ipAddress.fqdn -o tsv
az container show --name parse-dashboard --resource-group "$RG" --query ipAddress.fqdn -o tsv
```

---

## Optional: HTTPS Frontend

ACI does not provide TLS termination. To expose HTTPS you can either:

- Place Azure Application Gateway / Front Door in front of the dashboard, or
- Deploy an additional reverse-proxy container (e.g., NGINX) that serves 443 and forwards to port 4040 with your certificates mounted as secrets.

---

## Cleanup

Remove every deployed resource when finished:

```bash
az group delete --name ${RESOURCE_GROUP_NAME:-TikTik_Multi_2_RG} --yes --no-wait
```

---

## Troubleshooting

- View container logs:

  ```bash
  RG=${RESOURCE_GROUP_NAME:-TikTik_Multi_2_RG}
  az container logs --name mongodb --resource-group "$RG"
  az container logs --name parse-server --resource-group "$RG"
  az container logs --name parse-dashboard --resource-group "$RG"
  ```

- Redeploy a single component by rerunning its script.
- Ensure `.env` contains all required keys; the scripts will stop early if any are missing.

---

Happy deploying!
