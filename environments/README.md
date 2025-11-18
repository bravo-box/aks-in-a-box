# Environment Configuration Files

This directory contains environment-specific configuration files for deploying AKS infrastructure to different Azure subscriptions.

## Environment Files

- `.env.dev` - Development environment configuration
- `.env.test` - Test environment configuration
- `.env.prod` - Production environment configuration

## Configuration Variables

Each environment file contains the following variables:

### Azure Configuration
- `CLOUD_ENV` - Azure cloud environment (AzureCloud or AzureUSGovernment)
- `LOCATION` - Azure region for deployment (e.g., eastus, westus, usgovvirginia)

### Resource Group Configuration
- `CREATE_RG` - Whether to create a new resource group (y/n)
- `RESOURCE_GROUP` - Resource group name

### Key Vault and Storage Configuration
- `CREATE_PREDEPLOY` - Whether to create Key Vault and Storage Account (y/n)
- `KV_NAME` - Key Vault name (must be globally unique)
- `SA_NAME` - Storage Account name (must be globally unique, alphanumeric only)

### User Assigned Managed Identity Configuration
- `CREATE_UAMI` - Whether to create a new UAMI (y/n)
- `UAMI_NAME` - User Assigned Managed Identity name

### Project Configuration
- `PROJECT_NAME` - Project name (max 5 characters, lowercase, no spaces/special chars)

### Network Configuration
- `existingVNETName` - Existing virtual network name
- `SUBNET_PREFIX` - IP address prefix for the new subnet (e.g., 10.0.1.0)

### Jumpbox Configuration
- `ADMIN_NAME` - Admin username for jumpboxes

### AKS Configuration
- `ADMIN_GROUP_ID` - Entra ID Group Object ID for AKS Admins

### Tags
- `COST_CENTER` - Cost center tag value
- `ENVIRONMENT` - Environment tag (Dev, Test, Prod)

### ARM Template Configuration
- `TEMPLATE_FILE` - Path to ARM template file
- `DEPLOYMENT_NAME` - Name for the deployment

## GitHub Secrets Required

When using these configurations with GitHub Actions, ensure the following secrets are configured:

### For Azure Authentication
- `AZURE_CREDENTIALS_DEV` - Azure service principal credentials for dev environment
- `AZURE_CREDENTIALS_TEST` - Azure service principal credentials for test environment
- `AZURE_CREDENTIALS_PROD` - Azure service principal credentials for prod environment

### For Jumpbox Configuration
- `JUMPBOX_ADMIN_PASSWORD` - Admin password for jumpboxes (at least 12 characters)

### Format of AZURE_CREDENTIALS
```json
{
  "clientId": "<service-principal-client-id>",
  "clientSecret": "<service-principal-secret>",
  "subscriptionId": "<azure-subscription-id>",
  "tenantId": "<azure-tenant-id>"
}
```

## Creating Azure Service Principal

To create a service principal for GitHub Actions:

```bash
az ad sp create-for-rbac --name "github-actions-aks-{env}" \
  --role contributor \
  --scopes /subscriptions/{subscription-id} \
  --sdk-auth
```

## Usage

1. Update the environment file with your specific values
2. Configure the required GitHub secrets in your repository
3. Trigger the GitHub Actions workflow with the desired environment

## Important Notes

- Key Vault and Storage Account names must be globally unique
- Storage Account names can only contain lowercase letters and numbers
- Project names must be 5 characters or less
- Ensure your virtual network exists before running the deployment
- The ADMIN_GROUP_ID must be a valid Entra ID group object ID
