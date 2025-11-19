# Parse Server Deployment Demo

A demonstration project showing how to deploy a Parse Server stack with MongoDB and Parse Dashboard using Docker Compose (local) and Azure Container Instances (cloud).

## What's Included

This stack includes three components:

- **MongoDB 8.2.1**: Database backend
- **Parse Server 8.3.0**: Application backend (REST/GraphQL API)
- **Parse Dashboard 8.0.0**: Web-based admin interface

## Quick Start (Local)

1. **Copy the environment template:**

   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` with your credentials:**

   ```bash
   # Minimum required variables for local deployment:
   MONGO_INITDB_ROOT_USERNAME=admin
   MONGO_INITDB_ROOT_PASSWORD=your-secure-password
   PARSE_SERVER_APPLICATION_ID=myAppId
   PARSE_SERVER_MASTER_KEY=myMasterKey
   ```

3. **Start the stack:**

   ```bash
   docker compose up -d
   ```

4. **Access the services:**
   - Parse Dashboard: <http://localhost:4040>
   - Parse Server API: <http://localhost:1337/parse>
   - MongoDB: localhost:27017

## Azure Deployment

For production deployment to Azure Container Instances:

1. **Configure Azure variables in `.env`:**

   ```bash
   RESOURCE_GROUP_NAME=TikTik_Multi_2_RG
   AZURE_REGION=switzerlandnorth
   STORAGE_ACCOUNT_NAME=your-storage-account
   ```

2. **Login to Azure:**

   ```bash
   az login
   ```

3. **Deploy the stack:**

   ```bash
   chmod +x deploy-all.sh
   ./deploy-all.sh
   ```

## Project Structure

```text
.
├── docker-compose.yml           # Local Docker Compose configuration
├── .env.example                 # Environment variables template
├── deploy-all.sh                # Azure deployment orchestrator
├── deploy-mongodb.sh            # MongoDB Azure deployment
├── deploy-parse-server.sh       # Parse Server Azure deployment
├── deploy-parse-dashboard.sh    # Dashboard Azure deployment
├── mongodb-deploy.yaml          # MongoDB ACI template
├── parse-server-deploy.yaml     # Parse Server ACI template
└── parse-dashboard-deploy.yaml  # Dashboard ACI template
```

## Documentation

For detailed information about:

- Environment configuration
- Local development workflows
- Azure deployment architecture
- Troubleshooting and management

See [CLAUDE.md](CLAUDE.md) for comprehensive documentation.

## Use Case

This project demonstrates:

- Multi-container orchestration with Docker Compose
- Environment-based configuration management
- Cloud deployment to Azure Container Instances
- MongoDB persistence using Azure File Shares
- Parse Server as a Backend-as-a-Service (BaaS)

Perfect for learning Parse Server deployment patterns or as a starting point for small-to-medium Parse applications.
