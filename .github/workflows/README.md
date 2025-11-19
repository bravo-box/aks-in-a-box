# GitHub Actions Workflow - Quick Reference

## Overview

The GitHub Actions workflow automates the deployment of AKS infrastructure to Azure subscriptions. It supports multiple environments and both Azure Commercial and Azure Government clouds.

## Workflow File

`.github/workflows/deploy-infrastructure.yml`

## How to Use

### 1. Configure GitHub Secrets

Navigate to your repository's Settings > Secrets and variables > Actions, and add:

| Secret Name | Description | Example Format |
|-------------|-------------|----------------|
| `AZURE_CREDENTIALS_DEV` | Azure SP credentials for dev | JSON (see below) |
| `AZURE_CREDENTIALS_TEST` | Azure SP credentials for test | JSON (see below) |
| `AZURE_CREDENTIALS_PROD` | Azure SP credentials for prod | JSON (see below) |
| `JUMPBOX_ADMIN_PASSWORD` | Password for jumpbox VMs | Min 12 characters |

#### Azure Credentials JSON Format

```json
{
  "clientId": "00000000-0000-0000-0000-000000000000",
  "clientSecret": "your-client-secret",
  "subscriptionId": "00000000-0000-0000-0000-000000000000",
  "tenantId": "00000000-0000-0000-0000-000000000000"
}
```

#### Creating a Service Principal

```bash
# For dev environment
az ad sp create-for-rbac --name "github-actions-aks-dev" \
  --role contributor \
  --scopes /subscriptions/{subscription-id} \
  --sdk-auth

# For test environment
az ad sp create-for-rbac --name "github-actions-aks-test" \
  --role contributor \
  --scopes /subscriptions/{subscription-id} \
  --sdk-auth

# For prod environment
az ad sp create-for-rbac --name "github-actions-aks-prod" \
  --role contributor \
  --scopes /subscriptions/{subscription-id} \
  --sdk-auth
```

Copy the entire JSON output and paste it as the secret value.

### 2. Configure Environment Files

Edit the environment configuration files in the `environments/` directory:

- `environments/.env.dev` - Development environment
- `environments/.env.test` - Test environment
- `environments/.env.prod` - Production environment

Key configurations to update:

```bash
# Azure configuration
CLOUD_ENV=AzureCloud                    # or AzureUSGovernment
LOCATION=eastus                         # Azure region

# Resource naming
RESOURCE_GROUP=rg-aks-dev              # Resource group name
KV_NAME=kv-aks-dev                     # Key Vault name (must be globally unique)
SA_NAME=saaksdev                       # Storage account name (must be globally unique)
UAMI_NAME=uami-aks-dev                 # User Assigned Managed Identity name
PROJECT_NAME=akdev                      # Project name (max 5 chars)

# Network configuration
existingVNETName=vnet-dev              # Existing vNet name
SUBNET_PREFIX=10.0.1.0                 # New subnet prefix

# AKS configuration
ADMIN_NAME=aksadmin                    # Jumpbox admin username
ADMIN_GROUP_ID=                        # Entra ID Group Object ID for AKS admins

# Tags
COST_CENTER=DEV-001                    # Cost center tag
ENVIRONMENT=Dev                        # Environment tag
```

### 3. Run the Workflow

1. Go to your repository on GitHub
2. Click the "Actions" tab
3. Select "Deploy AKS Infrastructure" from the left sidebar
4. Click "Run workflow" button
5. Fill in the inputs:
   - **Environment**: Choose `dev`, `test`, or `prod`
   - **Azure Cloud Type**: Choose `AzureCloud` or `AzureUSGovernment`
6. Click "Run workflow" to start

## Workflow Steps

1. **Checkout repository** - Gets the code
2. **Load environment configuration** - Loads variables from `.env.{environment}` file
3. **Azure Login** - Authenticates to Azure using service principal
4. **Set Azure Cloud** - Configures Azure CLI for selected cloud
5. **Prepare environment file** - Creates temporary env file for deployment script
6. **Validate prerequisites** - Checks Azure subscription and permissions
7. **Deploy infrastructure** - Runs the `deploy_infra.sh` script
8. **Deployment summary** - Outputs deployment details
9. **Upload deployment artifacts** - Saves parameters file for reference
10. **Cleanup** - Removes temporary files

## Environment Variables

The workflow sets these environment variables for the deployment script:

| Variable | Source | Description |
|----------|--------|-------------|
| `CLOUD_ENV` | Workflow input | Azure cloud environment |
| `ADMIN_PASSWORD` | GitHub Secret | Jumpbox admin password |
| `AUTO_APPROVE` | Workflow | Set to `true` to skip confirmations |
| All other variables | Environment file | From `environments/.env.{environment}` |

## Troubleshooting

### Workflow fails with "Not logged in to Azure"

- Check that the `AZURE_CREDENTIALS_{ENV}` secret is correctly configured
- Verify the service principal has not expired
- Ensure the secret is valid JSON

### Workflow fails with "Environment file not found"

- Verify the environment file exists: `environments/.env.{environment}`
- Check the environment name in the workflow input matches the file name

### Deployment fails with "Permission denied"

- Verify the service principal has `Contributor` role on the subscription
- Check that the resource group/resources don't already exist with different permissions

### Deployment fails with "Key Vault name already exists"

- Key Vault names must be globally unique
- Update the `KV_NAME` in your environment file to a unique value

### Deployment fails with "Storage account name already exists"

- Storage account names must be globally unique
- Update the `SA_NAME` in your environment file to a unique value
- Remember: Storage account names must be 3-24 characters, lowercase letters and numbers only

## Monitoring Deployment

- View real-time logs in the Actions tab during workflow execution
- Download deployment artifacts after completion:
  - `infra.parameters.json` - Generated ARM template parameters
  - `.temp.infra.env` - Temporary environment file used
- Check the deployment summary in the workflow run for key details

## Security Best Practices

1. **Protect secrets**: Never commit secrets to the repository
2. **Use separate subscriptions**: Use different Azure subscriptions for dev/test/prod
3. **Rotate credentials**: Regularly rotate service principal secrets
4. **Limit permissions**: Grant minimum required permissions to service principals
5. **Review deployments**: Always review deployment logs for sensitive information
6. **Use environments**: Configure GitHub environment protection rules for prod

## Additional Resources

- [Environments README](../environments/README.md) - Detailed environment configuration guide
- [Main README](../README.md) - Full project documentation
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Azure Service Principal Documentation](https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal)
