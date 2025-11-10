# AKS-in-a-Box

This is written as a quickstart to show how to deploy Azure Kubernetes Service (AKS). For a deep dive on AKS be sure to visit the Microsoft Learn content for concepts and architectures.

https://learn.microsoft.com/en-us/azure/aks/core-aks-concepts

https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/containers/aks-mission-critical/mission-critical-intro

The jumpstart architecture we are building is comprised of:

- Azure Kubernetes Service deployed as a private cluster, FIPS enabled with 2 node pools and Entra ID integrated.
- Azure Container Registry with a private endpoint and private DNS zone
- Deploys a subnet to an existing vNet and creates network security group and route table
- Two jumpboxes deployed to the same subnet as the AKS cluster, one Linux and one Windows. These are to do AKS administration as it is deployed as a private cluster. If your Azure networking is already connected to your deployment machine you likely will not need these.
- Bash script to provision the Linux box post deployment. The enables all the tools required (Az CLI, GH CLI, Helm, Net Tools, KubeCtl, Kubelogin)
- KeyVault
- Storage Account for the cluster and Splunk Apps
- User Assigned Managed Identity for cluster operations

**There is an architectural diagram of the deployed solution found [here](./docs/architecture.md).**

## Assumptions

It is assumed that there is a vNet already in place and that you have an Azure Bastion service already enabled for connectivity to the jumbox VMs. If these are not present, you will need to create before proceeding.

Here is a simple example if you dont have a vNet or Bastion as yet.

```bash
az network vnet create \
    --resource-group <resource-group-name> \
    --name <vnet-name> \
    --address-prefixes <vnet-address-prefix> \
    --location <location>

az network bastion create \
  --location <region> \
  --name <bastion-host-name> \
  --public-ip-address <public-ip-address-name> \
  --resource-group <resource-group-name> \
  --vnet-name <virtual-network-name> \
  --sku Standard
```

## Automated Deployment for the Infrastructure (Recommended)

These tasks can be done either through cli, powershell, vscode task or the portal.

### Available Tasks

#### Infrastructure Tasks
- **Login to Azure Commercial** - Performs an az login against azure commercial.
- **Login to Azure Government** - Performs an az login against azure government.
- **Deploy Infrastructure** - Runs the `deploy_infra.sh` script to provision all required Azure resources including Resource Group, Key Vault, Storage Account, and User Assigned Managed Identity

### Running Tasks
To execute any task:
1. Open the Command Palette (`Ctrl+Shift+P` or `Cmd+Shift+P`)
2. Type "Tasks: Run Task"
3. Select the desired task from the list
4. Follow any prompts for required parameters

Throughout this readme, the az cli commands that you can run to do the manual configs. We have also provided a full bash script that will build the entire infrastructure for you.

The deploy_infra.sh can create a Resource Group for the prerequisites, Key Vault, Storage Account and User Assigned Managed Identity (UAMI). The bash script will also assign the necessary roles to the UAMI. Once the prereqs are complete the bash script will build the parameter file and deploy the ARM template (infra.json).
Should you decide to use the bash file (recommended approach):

```bash
chmod +x deploy_infra.sh
./deploy_infra.sh
```

You will be prompted for the following, you can chose not to deploy the RG, KV, Storage Account and UAMI. You will need to provide details of them and they will need to be in the same resource group.

1. The cloud you are using, AzureCloud or AzureUSGovernment
2. The location of the resources, use the name of the location not the display name. eg: westus or usgovvirginia. Note that this should be the same as the vNet that you are going to be building in.
3. Resource Group for the KeyVault, Storage Account and UAMI
4. KeyVault name - it will append a 10 digit random number to the end of the name eg: kv-test entered will become kv-testabc123de90
5. Storage Account name - same as above, it will append the 10 digit random number. Note storage accounts can only accecpt alpah numeric, no special characters.
6. User Assigned Managed Identity (UAMI). You can chose to use an existing UAMI if you have one
7. Project name - this is name that will be used to name all resources in this deployment. Should be greater than 5 characters and no spaces or special characters eg: alpha
8. Existing vNet name (we will detect the resource group name and present the subnets and address space that are already in the vNet)
9. Enter the IP address space for the cluster. By default this deployment will provision a /27. You only need to enter the x.x.x.x eg: 10.0.1.0.
10. Enter the username for your jumpboxes
11. Enter the password for the jumboxes
12. Group ID from Entra. This is a group that will be used to manage access to the AKS Cluster. You can get this from Entra ID
13. Tag Cost Center, if you dont use press enter and it will assign n/a
14. Tag Env, this is Dev, Test, Prod. If you dont use tags then enter to skip it will add n/a

## Manual Deployment

### Creating the keyVault

```cli
az cloud set AzureCloud or AzureUSGovernment
az login --use-device-code

rg="<your_RG_Name>"
SUBSCRIPTION_ID="<sub-id>"
location="<location>"
uami_name="<UAMI Name>"
storage_account_name="<storage name>"
$kv_name="keyVault Name"

az keyvault create -n <kvname> -g <your_RG> -location <location>
```

#### Note your keyvault name needs to be globally unique

### Creating the Storage Account

```cli
az storage account create -n <storageacctname> -g <your_RG> -location <region>  --min-tls-version TLS1_2  --allow-blob-public-access false
```

#### Note your keyvault name needs to be globally unique and no special characters, uppercase or spaces or dashes

Reference for Azure naming requirements here: https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules

### Creating the User Assigned Managed Identity

```cli
az identity create -n $uami_name -g $rg$ -location $location
```

Once you have created these resources you will need to assign the following rights to the UAMI you have just created. We are using least required privledge, the reason for the Managed Identity Operator is that as AKS deploys it creates the underlying infrastructure in a managed resource group which would inherit the role. 

- Storage Blob Data Reader on the storage account
- Key Vault Certificate User on the keyVault
- Key Vault Crypto User on the keyVault
- Key Vault Secrets User on the keyVault
- Managed Identity Operator at the subscription

```cli
# Define your parameters
UAMI_PRINCIPAL_ID=$(az identity show -n $uami_name -g $rg --query "principalId" -o tsv)
STORAGE_ACCOUNT_ID="az storage account show -n $storage_account_name -g $rg --query "id" -o tsv"
KEYVAULT_ID="az keyvault show -n $kv_name -g $rg --query "id" -o tsv"

az role assignment create \
  --assignee $UAMI_PRINCIPAL_ID \
  --role "Storage Blob Data Reader" \
  --scope $STORAGE_ACCOUNT_ID

for role in "Key Vault Certificate User" "Key Vault Crypto User" "Key Vault Secrets User"; do
  az role assignment create \
    --assignee $UAMI_PRINCIPAL_ID \
    --role "$role" \
    --scope $KEYVAULT_ID
done

az role assignment create \
  --assignee $UAMI_PRINCIPAL_ID \
  --role "Managed Identity Operator" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"


az keyvault key create --vault-name <vault name> -n aks-cmk
```

Now that you have all the prerequisites done. We are ready to deploy the infrastructure template.

## AKS Deployment

The ARM template provided will build all the infrastructure needed to standup the AKS infra, this includes the AKS cluster, Azure Container Registry, networking components and jumpboxes.
It is important to note that this deployment is deployed as a private cluster. All resources are deployed to an existing vNet however we create a subnet in the vNet. The subnet created by default is a /27, should you need to make it bigger adjust the prefix in the ARM template (row 491). Ensure that the prefix that you use in the parameter file can support the address space if you change it. The jumpboxes are deployed into the subnet you define.
For the subnet there is an NSG and RT that gets builts you have the choice of deploying the routes to the route table.
Before you deploy verify all the details in the parameter file, you will need to capture the following:

You can get your public IP for the ACR firewall rule here, you can place this in the parameter file for the infrastructure deployment.

```bash
curl -s https://ifconfig.me | awk '{print $1}')
```

Contents for infra.parameter.json

```json
{
    "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "location": { 
          "value": "" 
          },
        "projectName": { 
          "value": "" 
          },
        "createdbyTag": { 
          "value": "" 
          },
        "costcenter": { 
          "value": "" 
          },
        "Env": { 
          "value": "" 
          },
        "adminUsername": {
            "metadata": { "description": "Admin username for the jumpboxes. Must be between 1 and 20 characters long." },
            "value": ""
        },
        "adminPassword": {
            "metadata": { "description": "Admin password for the jumpboxes. Must be at least 12 characters long and meet complexity requirements." },
            "value": ""
        },
        "existingVNETName": {
            "metadata": { "description": "Name of the existing VNET" },
            "value": ""
        },
        "existingVnetResourceGroup": {
            "metadata": { "description": "Resource Group of the existing VNET" },
            "value": ""
        },
        "newSubnetAddressPrefix": {
            "metadata": { "description": "Address prefix for the new Subnet. Must be a subset of the existing VNET address space. AKS will deploy /27 all you need is the x.x.x.0" },
            "value": ""
        },
        "kubernetes_version": {
            "metadata": { "description": "Kubernetes version for the AKS Cluster." },
            "value": "1.33.2"
        },
        "clusterDNSprefix": {
            "metadata": { "description": "Enter the DNS prefix for the AKS Cluster." },
            "value": ""
        },
        "keyVaultName": {
            "metadata": { "description": "Key Vault Name to store secrets" },
            "value": ""
        },
        "keyName": {
            "metadata": { "description": "Key Vault Key Name to encrypt secrets" },
            "value": "aks-cmk"
        },
        "userAssignedID": {
            "metadata": { "description": "User Assigned Managed Identity Name" },
            "value": ""
        },
        "userIDRGName": {
            "metadata": { "description": "User Assigned Managed Identity Resource Group Name" },
            "value": ""
        },
        "keyVaultAccess": {
            "metadata": { "description": "Enable Key Vault access via public endpoint or private endpoint" },
            "value": "Public"
        },
        "adminGroupObjectIDs": {
            "metadata": { "description": "Entra ID Group Object IDs that will be assigned as AKS Admins" },
            "value": ""
        },
        "myIP": {
            "metadata": { "description": "Your public IP address for the ACR firewall rules" },
            "value": ""
            }
    }
}
```

Once you have captured / updated all the parameters in the infra.parameters.json file you can run the deployment.

** Note that this deployment is a subscription deployment not a resource group deployment

```json
az deployment sub create -n <deployment_name> -l <location> -f infra.json -p infra.parameters.json

# if you want to run a test first

az deployment sub create -n <deployment_name> -l <location> -f infra.json -p infra.parameters.json --what-if
```

Great, we now have all the resources ready to deploy the Splunk instance.
You have an AKS cluster with managed identity enabled. 

Things to verify before we move forward.

1. In the AKS cluster check the security settings have your group identity attached. You may need to change the drop down to Entra ID and kubernetes RBAC for it to be displayed.
2. Verify that OIDC and workload identity are enabled on the cluster, this can be found on the security configuration tab.

## Configuring the jumbox (Linux)

Lets get the linux jumpbox configured and ready to manage the cluster. Once you have connected to your Linux jumpbox VM using Bastion, run the following script to download the configuration script.

```bash
curl -sLO https://raw.githubusercontent.com/bravo-box/splunk-on-aks/refs/heads/main/setup_lin_jumpbox.sh && bash setup_lin_jumpbox.sh
```

This will setup the following resources on your jumpbox

- Azure CLI
- Go
- Make
- NetTools
- KubeLogin
- Kubectl
- Git CLI
- Helm

Once the tools are run do an Azure Login to ensure that you are have access to your environment

```bash
az cloud set AzureCloud or AzureUSGovernment
az login --use-device-code

az account show
```

Now that we have access to the Azure environment from the Azure Linux jumpbox, we will need to get the AKS credentials into your kubeconfig file.

```bash
rg=<resource group name>
cn=<cluster name>

az aks get-credentials -n $cn -g $rg
```

Should see a message that your cluster details have been merged into your kubeconfig file.
It should also show the following: convert-kubeconfig -l azurecli

If not, we will need to ensure that kubelogin is configured correctly. We do this by running the kubelogin command to activate via Az CLI.

```bash
kubelogin convert-kubeconfig -l azurecli
```

To test you can now run the following against your cluster

```kubectl
kubectl get ns

# or

kubectl get pods -A

# or

kubectl cluster-info
```

You may be prompted to login in. Once you have logged in, you will be presented with the default namespaces in the cluster.

** The Windows jumpbox can be used as well, particularly for access to the portal. You can log into the azure portal and view the resources in your cluster. 

Remember as this is a private cluster you cannot see the resources from the portal if you are connecting from a machine that outside of your network eg: a home machine that is not on VPN or if you are on a network that is not peered and routed correctly to the network in Azure.

Next you would want to pull the repo for the splunk installation assets down to the jumpbox.

```bash
git clone https://github.com/bravo-box/splunk-on-aks.git
```