#!/usr/bin/env bash

#============================================================
# Title: Deploy Private AKS Cluster Infrastructure
#============================================================
# Infrastructure Deployment Script at Azure Subscription Scope to
# build out the necessary resources for an AKS Private Cluster with CMK, UAMI, Key Vault, and Storage Account.
# You will be prompted to create or use existing resources as needed.
# Prerequisites:
#   - Azure CLI installed
#   - Sufficient permissions to create resources and assign roles
#   - Ensure you can run bash scripts on your system
#   - vNet in your subscription and Bastion for connection to the jumpboxes
#============================================================

set -e

# --- PARSE COMMAND LINE ARGUMENTS ---
LOAD_SAVED_PARAMS="false"
AZURE_ENVIRONMENT=""
ADMIN_PASSWORD=""
AUTO_APPROVE="false"
DEFAULT_INFRA_PARAMS="false"
INFRA_PARAMETER_FILE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --load-saved-parameters)
      LOAD_SAVED_PARAMS="true"
      shift
      ;;
    --azure-environment)
      if [[ -n "$2" && "$2" != --* ]]; then
        AZURE_ENVIRONMENT="$2"
        shift 2
      else
        echo "Error: --azure-environment requires a value (AzureCloud or AzureUSGovernment)"
        exit 1
      fi
      ;;
    --admin-password)
      if [[ -n "$2" && "$2" != --* ]]; then
        ADMIN_PASSWORD="$2"
        shift 2
      else
        echo "Error: --admin-password requires a value (at least 12 characters)"
        exit 1
      fi
      ;;
    --auto-approve)
      AUTO_APPROVE="true"
      shift
      ;;
    --default-infra-parameters)
      DEFAULT_INFRA_PARAMS="true"
      shift
      ;;
    --infra-parameter-file)
      if [[ -n "$2" && "$2" != --* ]]; then
        INFRA_PARAMETER_FILE="$2"
        shift 2
      else
        echo "Error: --infra-parameter-file requires a value (path to parameter file)"
        exit 1
      fi
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--load-saved-parameters] [--azure-environment <AzureCloud|AzureUSGovernment>] [--admin-password <password>] [--auto-approve] [--default-infra-parameters] [--infra-parameter-file <path>]"
      exit 1
      ;;
  esac
done

# Validate admin password if provided via parameter
if [[ -n "$ADMIN_PASSWORD" && ${#ADMIN_PASSWORD} -lt 12 ]]; then
  echo "Error: --admin-password must be at least 12 characters long"
  exit 1
fi

# --- SOURCE MODULES ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARIABLE_MODULE_FILE="${SCRIPT_DIR}/modules/variable_mgmt.sh"
LOG_MODULE_FILE="${SCRIPT_DIR}/modules/logging.sh"
COMMAND_MODULE_FILE="${SCRIPT_DIR}/modules/command.sh"
ERROR_HANDLING_FILE="${SCRIPT_DIR}/modules/error_handling.sh"

if [[ ! -f "$VARIABLE_MODULE_FILE" ]]; then
  log_error "Required module not found: $VARIABLE_MODULE_FILE"
  exit 1
fi

if [[ ! -f "$LOG_MODULE_FILE" ]]; then
  log_error "Required module not found: $LOG_MODULE_FILE"
  exit 1
fi

if [[ ! -f "$COMMAND_MODULE_FILE" ]]; then
  log_error "Required module not found: $COMMAND_MODULE_FILE"
  exit 1
fi

if [[ ! -f "$ERROR_HANDLING_FILE" ]]; then
  log_error "Required module not found: $ERROR_HANDLING_FILE"
  exit 1
fi
source "$VARIABLE_MODULE_FILE"
source "$LOG_MODULE_FILE"
source "$COMMAND_MODULE_FILE"
source "$ERROR_HANDLING_FILE"

# Set up trap to call error_handler on any error (when set -e causes exit)
trap 'error_handler ${LINENO}' ERR

init_log_file
load_env "$LOAD_SAVED_PARAMS"

# --- DEFAULT VARIABLES ---
SPLUNK_IMAGE="${SPLUNK_IMAGE:-docker.io/splunk/splunk:9.4.5}"
OPERATOR_IMAGE="${OPERATOR_IMAGE:-docker.io/splunk/splunk-operator:3.0.0}"
MY_IP=$(curl -s https://ifconfig.me | awk '{print $1}')
RAND_SUFFIX=$(openssl rand -hex 5)

# Extract the part after the registry (e.g. "splunk/splunk:9.4.5" or "splunk/splunk-operator:3.0.0")
SPLUNK_TAG="${SPLUNK_IMAGE#*/}"  # Removes first part before first "/"
OPERATOR_TAG="${OPERATOR_IMAGE#*/}"  # Removes first part before first "/"

log_heading " Azure Subscription Deployment Script"

# --- SELECT AZURE CLOUD ---
# Check if parameter was provided and is valid
if [[ -n "$AZURE_ENVIRONMENT" ]]; then
  if [[ "$AZURE_ENVIRONMENT" == "AzureCloud" || "$AZURE_ENVIRONMENT" == "AzureUSGovernment" ]]; then
    CLOUD_ENV="$AZURE_ENVIRONMENT"
    log_info "Using Azure environment from parameter: $CLOUD_ENV"
    az cloud set --name "$CLOUD_ENV"
    set_variable "CLOUD_ENV" "$CLOUD_ENV"
  else
    log_info "Invalid --azure-environment value: $AZURE_ENVIRONMENT"
    log_info "Valid options are: AzureCloud, AzureUSGovernment"
    log_info "Falling back to interactive selection."
    AZURE_ENVIRONMENT=""
  fi
fi

# Check if already set from saved parameters
if [[ -z "$AZURE_ENVIRONMENT" && -n "$CLOUD_ENV" ]]; then
  log_info "Using existing Azure environment: $CLOUD_ENV"
  az cloud set --name "$CLOUD_ENV"
elif [[ -z "$AZURE_ENVIRONMENT" ]]; then
  # Interactive prompt if no parameter or saved value
  log_info "Select your Azure environment:"
  select CLOUD_ENV in "AzureCloud" "AzureUSGovernment"; do
    case $CLOUD_ENV in
      AzureCloud|AzureUSGovernment)
        log_info "Setting Azure cloud to: $CLOUD_ENV"
        az cloud set --name "$CLOUD_ENV"
        break
        ;;
      *)
        log_error "Invalid selection. Please choose 1 or 2."
        ;;
    esac
  done
  set_variable "CLOUD_ENV" "$CLOUD_ENV"
fi
echo

# --- LOGIN CHECK ---
if ! az account show &>/dev/null; then
  log_info "You are not logged in. Launching az login..."
  if ! az login --use-device-code >/dev/null 2>&1; then
    log_error "Azure login failed. Please check your credentials and try again."
    exit 1
  fi
  log_success "Login successful."
fi

# --- GET CURRENT SUBSCRIPTION ---
SUBSCRIPTION_ID=$(run_az_command "az account show --query id -o tsv" "Failed to get subscription ID")
SUBSCRIPTION_NAME=$(run_az_command "az account show --query name -o tsv" "Failed to get subscription name")
log_info "Using current subscription:"
log_info "  Name: $SUBSCRIPTION_NAME"
log_info "  ID:   $SUBSCRIPTION_ID"
echo

# --- SELECT LOCATION ---
log_info "Available Azure regions:"
az account list-locations --query "sort_by([].{Name:name, DisplayName:displayName}, &Name)" -o table
echo

LOCATION=$(prompt_variable "Enter the Azure region for deployment (e.g., eastus, westus or usgovirginia): " "LOCATION")
log_info "Selected location: $LOCATION"
echo

# --- CREATE OR USE EXISTING RESOURCE GROUP ---
CREATE_RG=$(prompt_y_or_n "Do you want to create a new Resource Group for shared services, KV, Storage, UAMI? (y/n): " "CREATE_RG")

  if [[ "$CREATE_RG" == "y" ]]; then
    echo
    RESOURCE_GROUP=$(prompt_variable "Enter new Resource Group name (e.g., myresourcegroup-rg): " "RESOURCE_GROUP")

  log_info "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
  run_az_command "az group create -n '$RESOURCE_GROUP' -l '$LOCATION'" "Failed to create resource group '$RESOURCE_GROUP'"
  log_success "Resource group created."

    else
      echo
      RESOURCE_GROUP=$(prompt_variable "Enter existing Resource Group name where your KV, Storage Account and UAMI exist: " "RESOURCE_GROUP")
    fi

    if ! az group show -n "$RESOURCE_GROUP" &>/dev/null; then
      log_error "Resource Group '$RESOURCE_GROUP' not found. Please verify and rerun the script."
      exit 1
    fi

  LOCATION=$(run_az_command "az group show -n '$RESOURCE_GROUP' --query 'location' -o tsv" "Failed to get location for resource group '$RESOURCE_GROUP'")
  log_success "Using existing Resource Group: $RESOURCE_GROUP (location: $LOCATION)"

# --- DEPLOY OR USE EXISTING KEY VAULT + STORAGE ACCOUNT ---
CREATE_PREDEPLOY=$(prompt_y_or_n "Do you want to deploy a Key Vault and Storage Account before the ARM template? (y/n): " "CREATE_PREDEPLOY")

if [[ "$CREATE_PREDEPLOY" == "y" ]]; then
  echo
  KV_NAME=$(prompt_variable "Enter Key Vault name (must be globally unique): " "KV_NAME")
  SA_NAME=$(prompt_variable "Enter Storage Account name (must be globally unique, 3-24 lowercase letters/numbers): " "SA_NAME")

  # Append it to the KV name (make sure to stay under Azure's 24-char limit for KV names)
  KV_NAME="${KV_NAME}${RAND_SUFFIX}"

  log_info "Creating Key Vault '$KV_NAME'..."
  run_az_command "az keyvault create -n '$KV_NAME' -g '$RESOURCE_GROUP' -l '$LOCATION'" "Failed to create Key Vault '$KV_NAME'"
  log_success "Key Vault created."

  # Append it to the SA name (make sure to stay under Azure's 24-char limit for SA names)
  SA_NAME="${SA_NAME}${RAND_SUFFIX}"

  log_info "Creating Storage Account '$SA_NAME'..."
  run_az_command "az storage account create -n '$SA_NAME' -g '$RESOURCE_GROUP' -l '$LOCATION' --min-tls-version TLS1_2 --allow-blob-public-access false" "Failed to create Storage Account '$SA_NAME'"
  log_success "Storage Account created."

  update_env_var "KV_NAME" "$KV_NAME"
  update_env_var "SA_NAME" "$SA_NAME"
  update_env_var "CREATE_PREDEPLOY" "n"

else
  echo
  log_info "ℹ️ Skipping deployment of new Key Vault and Storage Account."
  log_info "You will need to provide existing resource names."

  # --- PROMPT FOR EXISTING RESOURCES ---
  KV_NAME=$(prompt_variable "Enter existing Key Vault name: " "KV_NAME")
  SA_NAME=$(prompt_variable "Enter existing Storage Account name: " "SA_NAME")
  
  # --- VALIDATE EXISTENCE ---
  if ! az keyvault show -n "$KV_NAME" &>/dev/null; then
    log_error "Key Vault '$KV_NAME' not found. Please verify the name and rerun the script."
    exit 1
  fi

  if ! az storage account show -n "$SA_NAME" &>/dev/null; then
    log_error "Storage Account '$SA_NAME' not found. Please verify the name and rerun the script."
    exit 1
  fi

  log_success "Using existing Key Vault: $KV_NAME"
  log_success "Using existing Storage Account: $SA_NAME"
fi

  # --- CREATE USER-ASSIGNED MANAGED IDENTITY, ASSIGN ROLES ---
  echo
    # --- CREATE OR USE EXISTING USER-ASSIGNED MANAGED IDENTITY ---
    CREATE_UAMI=$(prompt_y_or_n "Do you want to create a new User-Assigned Managed Identity (UAMI)? (y/n): " "CREATE_UAMI")

    if [[ "$CREATE_UAMI" == "y" ]]; then
    echo
    UAMI_NAME=$(prompt_variable "Enter a name for the new UAMI: " "UAMI_NAME")

    log_info "Creating User-Assigned Managed Identity '$UAMI_NAME'..."
    run_az_command "az identity create -n '$UAMI_NAME' -g '$RESOURCE_GROUP' -l '$LOCATION'" "Failed to create UAMI '$UAMI_NAME'"
    log_success "UAMI '$UAMI_NAME' created."
    update_env_var "CREATE_UAMI" "n"
    else
    echo
    UAMI_NAME=$(prompt_variable "Enter existing UAMI name: " "UAMI_NAME")

    # Validate existence and get details
    if ! az identity show -n "$UAMI_NAME" -g "$RESOURCE_GROUP" &>/dev/null; then
        log_error "UAMI '$UAMI_NAME' not found in resource group '$RESOURCE_GROUP'. Please verify and rerun the script."
        exit 1
    fi

    log_success "Using existing UAMI '$UAMI_NAME'."
    fi

    # --- GET UAMI DETAILS ---
    UAMI_ID=$(run_az_command "az identity show -n '$UAMI_NAME' -g '$RESOURCE_GROUP' --query id -o tsv" "Failed to get UAMI resource ID")
    UAMI_PRINCIPAL_ID=$(run_az_command "az identity show -n '$UAMI_NAME' -g '$RESOURCE_GROUP' --query principalId -o tsv" "Failed to get UAMI principal ID")
    log_info "  ↳ Resource ID:   $UAMI_ID"
    log_info "  ↳ Principal ID:  $UAMI_PRINCIPAL_ID"

    # --- GET RESOURCE IDs ---
    STORAGE_ACCOUNT_ID=$(run_az_command "az storage account show -n '$SA_NAME' -g '$RESOURCE_GROUP' --query 'id' -o tsv" "Failed to get Storage Account ID")
    KEYVAULT_ID=$(run_az_command "az keyvault show -n '$KV_NAME' -g '$RESOURCE_GROUP' --query 'id' -o tsv" "Failed to get Key Vault ID")

    # Get deployer principal ID - works for both signed-in user and service principal
    if DEPLOYER_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null); then
      log_info "Using signed-in user principal ID for role assignments"
    else
      # Running as service principal (e.g., GitHub Actions)
      DEPLOYER_PRINCIPAL_ID=$(run_az_command "az account show --query user.name -o tsv" "Failed to get service principal ID")
      log_info "Using service principal for role assignments: $DEPLOYER_PRINCIPAL_ID"
    fi

    # Assign Key Vault Crypto Officer role to Key Vault management for current signed in user
    run_az_command "az role assignment create --assignee '$DEPLOYER_PRINCIPAL_ID' --role 'Key Vault Crypto Officer' --scope '/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME'" "Failed to assign Key Vault Crypto Officer role"
    
    # --- VALIDATE ROLE ASSIGNMENT ---
    log_info "Validating role assignment propagation...This can take up to 5 minutes."
    MAX_WAIT=300  # seconds
    INTERVAL=10   # seconds
    ELAPSED=0

    while true; do
        ASSIGNED=$(az role assignment list \
            --assignee "$DEPLOYER_PRINCIPAL_ID" \
            --role "Key Vault Crypto Officer" \
            --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME" \
            --query "length([])" -o tsv)

        if [[ "$ASSIGNED" -gt 0 ]]; then
            log_success "Role assignment confirmed."
            break
        fi

        if [[ "$ELAPSED" -ge "$MAX_WAIT" ]]; then
            log_error "Timeout waiting for role assignment to propagate."
            exit 1
        fi

        log_info "Waiting for role assignment to propagate... ($ELAPSED/$MAX_WAIT seconds)"
        sleep "$INTERVAL"
        ELAPSED=$((ELAPSED + INTERVAL))
    done
    
    log_success "Assigned 'Key Vault Crypto Officer' to deployer for key creation."

    log_info "Assigning roles to the UAMI..."
    # --- STORAGE ROLE ---
    run_az_command "az role assignment create --assignee '$UAMI_PRINCIPAL_ID' --role 'Storage Blob Data Reader' --scope '$STORAGE_ACCOUNT_ID'" "Failed to assign Storage Blob Data Reader role"
    log_success "Assigned 'Storage Blob Data Reader' on $SA_NAME"

    # --- KEY VAULT ROLES ---
    for role in "Key Vault Certificate User" "Key Vault Crypto User" "Key Vault Secrets User"; do
      run_az_command "az role assignment create --assignee '$UAMI_PRINCIPAL_ID' --role '$role' --scope '$KEYVAULT_ID'" "Failed to assign '$role' role"
      log_success "Assigned '$role' on $KV_NAME"
    done

    # --- MANAGED IDENTITY OPERATOR ROLE ---
    run_az_command "az role assignment create --assignee '$UAMI_PRINCIPAL_ID' --role 'Managed Identity Operator' --scope '/subscriptions/$SUBSCRIPTION_ID'" "Failed to assign Managed Identity Operator role"
    log_success "Assigned 'Managed Identity Operator' at subscription level"

    # --- CREATE KEY IN KEYVAULT ---
    log_info "Creating Key 'aks-cmk' in Key Vault '$KV_NAME'..."
    run_az_command "az keyvault key create --vault-name '$KV_NAME' -n aks-cmk" "Failed to create key 'aks-cmk' in Key Vault"
    log_success "Key 'aks-cmk' created in Key Vault '$KV_NAME'"

# --- GET PARAMETERS FOR ARM TEMPLATE ---
    # Get creator name - works for both signed-in user and service principal
    if CREATED_BY=$(az ad signed-in-user show --query displayName -o tsv 2>/dev/null); then
      log_info "Created by: $CREATED_BY"
    else
      # Running as service principal (e.g., GitHub Actions)
      CREATED_BY=$(run_az_command "az account show --query user.name -o tsv" "Failed to get service principal name")
      log_info "Created by service principal: $CREATED_BY"
    fi
    
    # Capture ProjectName from user
    while true; do
      PROJECT_NAME=$(prompt_variable "Enter your project Name for this deployment, lower case, no spaces or special characters, max 5 characters: " "PROJECT_NAME")
      if [[ ${#PROJECT_NAME} -le 5 ]]; then
        break
      else
        log_error "Project name must be no more than 5 characters. Please try again."
        # Clear the variable so prompt_variable will ask again
        unset PROJECT_NAME
        # Remove from env file if it was saved
        if [[ -f "$ENV_FILE_NAME" ]]; then
          sed -i '/^PROJECT_NAME=/d' "$ENV_FILE_NAME"
        fi
      fi
    done

    # List all vNets in the subscription that are bound to the location specified
    log_info "Existing vNets in location '$LOCATION':"
    VNET_LIST=$(az network vnet list --query "[?location=='$LOCATION'].{Name:name, ResourceGroup:resourceGroup}" -o table)
    log_info "vNets that you can use for your AKS Private Cluster based in the location $LOCATION:"
    echo "$VNET_LIST"

    # vNet name for your AKS Private Cluster
    existingVNETName=$(prompt_variable "Enter the name of your existing VNet (e.g., vnet1): " "existingVNETName")

    # Get vNet Resource Group name for your AKS Private Cluster
    existingVnetResourceGroup=$(run_az_command "az network vnet list --query \"[?name=='$existingVNETName'].resourceGroup\" -o tsv" "Failed to get vNet resource group")
    log_info "Using VNet Resource Group: $existingVnetResourceGroup"

    # Get the subnet list for the existing vNet
    SUBNET_LIST=$(az network vnet list --query "[?name=='$existingVNETName'].subnets[].{Name:name, Address:addressPrefix}" -o table)
    log_info "Existing subnets in VNet '$existingVNETName':"
    echo "$SUBNET_LIST"

    # Enter the IP Address prefix for the deployed subnet
    SUBNET_PREFIX=$(prompt_variable "Enter the IP Address prefix for the new subnet (e.g., 10.0.0.0) the template will add a /27 to the appendix: " "SUBNET_PREFIX")

    # Capture Admin User Name from user
    ADMIN_NAME=$(prompt_variable "Enter an admin user name for the jumpbox (1-20 characters): " "ADMIN_NAME")

    # Capture Admin Password from user or environment variable
    if [[ -z "$ADMIN_PASSWORD" ]]; then
      read -rsp "Enter an admin password for the jumpbox (at least 12 characters): " ADMIN_PASSWORD
      echo
      while [[ -z "$ADMIN_PASSWORD" || ${#ADMIN_PASSWORD} -lt 12 ]]; do
        read -rsp "Admin password must be at least 12 characters. Please enter a valid admin password: " ADMIN_PASSWORD
        echo
      done
    else
      log_info "Using ADMIN_PASSWORD from environment variable"
      if [[ ${#ADMIN_PASSWORD} -lt 12 ]]; then
        log_error "ADMIN_PASSWORD must be at least 12 characters long"
        exit 1
      fi
    fi
    
    # Enter the Entra group ID that will be used for AKS Admins
    ADMIN_GROUP_ID=$(prompt_variable "Enter the Entra ID Group Object ID for AKS Admins (e.g., 558a10de-c70a-43fd-9400-0d56c0d49a2c): " "ADMIN_GROUP_ID")

    # Enter the Cost Center tag value
    COST_CENTER=$(prompt_variable "Enter your Cost Center (e.g., 12345, leave blank for n/a): " "COST_CENTER")

    # Enter the Environment tag value
    ENVIRONMENT=$(prompt_variable "Enter your Environment tag value (e.g., Dev, Test, Prod): " "ENVIRONMENT")
    ENVIRONMENT=${ENVIRONMENT:-n/a}
    log_info "ENVIRONMENT set to: $ENVIRONMENT"


    log_info "Getting parameters for ARM template..."
    log_info "  ↳ Created By:           $CREATED_BY"
    log_info "  ↳ Project Name:         $PROJECT_NAME"
    log_info "  ↳ Location:             $LOCATION"
    log_info "  ↳ vNet Name:            $existingVNETName"
    log_info "  ↳ vNet RG:              $existingVnetResourceGroup"
    log_info "  ↳ Subnet Prefix:        $SUBNET_PREFIX"
    log_info "  ↳ Key Vault Name:       $KV_NAME"
    log_info "  ↳ Storage Account:      $SA_NAME"
    log_info "  ↳ UAMI Name:            $UAMI_NAME"
    log_info "  ↳ Admin User Name:      $ADMIN_NAME"
    log_info "  ↳ Admin Password:       (hidden)"
    log_info "  ↳ Entra Admin Group ID: $ADMIN_GROUP_ID"    

  # --- FINAL CONFIRMATION BEFORE TEMPLATE DEPLOYMENT ---
  echo
  echo "----------------------------------------------"
  log_success "Prerequisite resources have been successfully deployed / verified and roles assigned:"
  log_info "   - Resource Group: $RESOURCE_GROUP"
  log_info "   - Key Vault: $KV_NAME"
  log_info "    ↳ Key created in Key Vault: aks-cmk"
  log_info "   - Storage Account: $SA_NAME"
  log_info "   - UAMI: $UAMI_NAME"
  
  echo "----------------------------------------------"
  echo
  if [[ "${AUTO_APPROVE}" == "true" ]]; then
    log_info "AUTO_APPROVE is set, proceeding with ARM template deployment automatically"
    CONFIRM_DEPLOY="y"
  else
    while true; do
      read -rp "Proceed with ARM template deployment? (y/n): " CONFIRM_DEPLOY
      CONFIRM_DEPLOY=$(echo "$CONFIRM_DEPLOY" | tr '[:upper:]' '[:lower:]')
      if [[ "$CONFIRM_DEPLOY" =~ ^[yn]$ ]]; then
        break
      else
        log_error "Please answer 'y' or 'n'."
      fi
    done
  fi
  if [[ "$CONFIRM_DEPLOY" == "n" ]]; then
    log_info "Deployment cancelled after prerequisites."
    exit 0
  fi

# --- GET TEMPLATE INFO ---
# Find template file relative to script directory
TEMPLATE_FILE="${SCRIPT_DIR}/../template/infra.json"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  log_error "Template file not found: $TEMPLATE_FILE"
  log_error "Expected location: <repo-root>/template/infra.json"
  exit 1
fi

log_info "Using template file: $TEMPLATE_FILE"

# Handle parameter file based on flags
if [[ "${DEFAULT_INFRA_PARAMS}" == "true" ]]; then
  PARAM_FILE=""
  log_info "Will generate parameters file from inputs"
else
  # Check if parameter file was provided via command line
  if [[ -n "$INFRA_PARAMETER_FILE" ]]; then
    PARAM_FILE="$INFRA_PARAMETER_FILE"
    if [[ ! -f "$PARAM_FILE" ]]; then
      log_error "Parameter file not found: $PARAM_FILE"
      exit 1
    fi
    log_info "Using parameter file from command line: $PARAM_FILE"
  else
    read -rp "Enter full path to parameters file (.json) [Press Enter to skip, if you skip we will create based on your input]: " PARAM_FILE
    if [[ -n "$PARAM_FILE" && ! -f "$PARAM_FILE" ]]; then
      log_info "⚠️ Parameter file not found. Ignoring and deploying without parameters."
      PARAM_FILE=""
    fi
  fi
fi

DEPLOYMENT_NAME=$(prompt_variable "Enter a name for this deployment [Press Enter for default]: " "DEPLOYMENT_NAME")
DEPLOYMENT_NAME=${DEPLOYMENT_NAME:-sub-deploy-$(date +%Y%m%d%H%M%S)}

# --- SUMMARY ---
echo
log_heading "Deployment Summary"

log_info "Cloud Environment: $CLOUD_ENV"
log_info "Subscription:      $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
log_info "Location:          $LOCATION"
log_info "Resource Group:    $RESOURCE_GROUP"
if [[ "$CREATE_PREDEPLOY" == "y" ]]; then
  log_info "Key Vault:         ${KV_NAME:-N/A}"
  log_info "Storage Account:   ${SA_NAME:-N/A}"
  [[ "$CREATE_UAMI" == "y" ]] && log_info "UAMI:              ${UAMI_NAME:-N/A}"
fi
log_info "Template File:     $TEMPLATE_FILE"
[[ -n "$PARAM_FILE" ]] && log_info "Parameters File:   $PARAM_FILE" || log_info "Parameters File:   (none)"
log_info "Deployment Name:   $DEPLOYMENT_NAME"
echo "----------------------------------------------"
echo

if [[ "${AUTO_APPROVE}" == "true" ]]; then
  log_info "AUTO_APPROVE is set, confirming final deployment automatically"
  CONFIRM_FINAL="y"
else
  while true; do
    read -rp "Confirm final deployment to subscription scope? (y/n): " CONFIRM_FINAL
    CONFIRM_FINAL=$(echo "$CONFIRM_FINAL" | tr '[:upper:]' '[:lower:]')
    if [[ "$CONFIRM_FINAL" =~ ^[yn]$ ]]; then
      break
    else
      log_error "Please answer 'y' or 'n'."
    fi
  done
fi
if [[ "$CONFIRM_FINAL" == "n" ]]; then
  log_info "Deployment cancelled."
  exit 0
fi

# --- GENERATE PARAMETERS FILE ---
echo
log_heading "📄 Generating ARM parameters file: infra.parameters.json"

cat > infra.parameters.json <<EOF
{
    "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "location": { "value": "${LOCATION}" },
        "projectName": { "value": "${PROJECT_NAME}" },
        "createdbyTag": { "value": "${CREATED_BY}" },
        "costcenter": { "value": "${COST_CENTER}" },
        "Env": { "value": "${ENVIRONMENT}" },
        "adminUsername": {
            "metadata": { "description": "Admin username for the jumpboxes. Must be between 1 and 20 characters long." },
            "value": "$ADMIN_NAME"
        },
        "adminPassword": {
            "metadata": { "description": "Admin password for the jumpboxes. Must be at least 12 characters long and meet complexity requirements." },
            "value": "$ADMIN_PASSWORD"
        },
        "existingVNETName": {
            "metadata": { "description": "Name of the existing VNET" },
            "value": "$existingVNETName"
        },
        "existingVnetResourceGroup": {
            "metadata": { "description": "Resource Group of the existing VNET" },
            "value": "$existingVnetResourceGroup"
        },
        "newSubnetAddressPrefix": {
            "metadata": { "description": "Address prefix for the new Subnet. Must be a subset of the existing VNET address space. AKS will deploy /27 all you need is the x.x.x.0" },
            "value": "$SUBNET_PREFIX"
        },
        "kubernetes_version": {
            "metadata": { "description": "Kubernetes version for the AKS Cluster." },
            "value": "1.33.2"
        },
        "clusterDNSprefix": {
            "metadata": { "description": "Enter the DNS prefix for the AKS Cluster." },
            "value": "$PROJECT_NAME"
        },
        "keyVaultName": {
            "metadata": { "description": "Key Vault Name to store secrets" },
            "value": "$KV_NAME"
        },
        "keyName": {
            "metadata": { "description": "Key Vault Key Name to encrypt secrets" },
            "value": "aks-cmk"
        },
        "userAssignedID": {
            "metadata": { "description": "User Assigned Managed Identity Name" },
            "value": "$UAMI_NAME"
        },
        "userIDRGName": {
            "metadata": { "description": "User Assigned Managed Identity Resource Group Name" },
            "value": "$RESOURCE_GROUP"
        },
        "keyVaultAccess": {
            "metadata": { "description": "Enable Key Vault access via public endpoint or private endpoint" },
            "value": "Public"
        },
        "adminGroupObjectIDs": {
            "metadata": { "description": "Entra ID Group Object IDs that will be assigned as AKS Admins" },
            "value": "$ADMIN_GROUP_ID"
        },
        "myIP": {
            "metadata": { "description": "Your public IP address for the ACR firewall rules" },
            "value": "$MY_IP"
            }
    }
}
EOF

PARAM_FILE="$(pwd)/infra.parameters.json"

log_heading "✅ Parameters file created: $PARAM_FILE"
echo

# --- DEPLOY ARM TEMPLATE USING GENERATED PARAMETERS FILE ---
DEPLOYMENT_NAME="${PROJECT_NAME}-deploy-$(date +%Y%m%d%H%M)"
capture_configuration
log_info "Starting subscription-scope ARM deployment: $DEPLOYMENT_NAME"
run_az_command "az deployment sub create --name '$DEPLOYMENT_NAME' --location '$LOCATION' --template-file '$TEMPLATE_FILE' --parameters @'$PARAM_FILE'" "ARM template deployment failed"

log_heading "✅ ARM deployment completed: $DEPLOYMENT_NAME"

# Assign Network Contributor role to UAMI for AKS Ingress deployments
log_info "Assigning network role to the UAMI for AKS Ingress deployments..."
    # --- NETWORK ROLE ---
    # Get subnet ID
    SUBNET_ID=$(run_az_command "az network vnet subnet show -g '$existingVnetResourceGroup' --vnet-name '$existingVNETName' -n '${PROJECT_NAME}-aks-snet' --query 'id' -o tsv" "Failed to get subnet ID")

    # Assign role to the UAMI
    run_az_command "az role assignment create --assignee '$UAMI_PRINCIPAL_ID' --role 'Network Contributor' --scope '$SUBNET_ID'" "Failed to assign Network Contributor role to subnet"

# Assign ACR Pull role to UAMI for AKS ACR access
log_info "Assigning ACR Pull role to the UAMI for AKS ACR access..."
    # --- ACR PULL ROLE ---
    # Get ACR name
    ACR_NAME=$(run_az_command "az acr list -g 'rg-$PROJECT_NAME' --query \"[?starts_with(name, '${PROJECT_NAME}')].name\" -o tsv" "Failed to get ACR name")
    ACR_ID=$(run_az_command "az acr show -n '$ACR_NAME' -g 'rg-$PROJECT_NAME' --query 'id' -o tsv" "Failed to get ACR ID")

    # Assign ACR Pull role to the UAMI
    run_az_command "az role assignment create --assignee '$UAMI_PRINCIPAL_ID' --role 'AcrPull' --scope '$ACR_ID'" "Failed to assign AcrPull role to UAMI"

# Assign ACR Push and Pull role for current signed in user
log_info "Assigning ACR Push role to the current user for AKS ACR access..."
    # --- ACR PUSH ROLE ---
    # Get current user principal ID
    if CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null); then
      log_info "Assigning ACR roles to signed-in user"
    else
      # Running as service principal (e.g., GitHub Actions)
      CURRENT_USER_ID=$(run_az_command "az account show --query user.name -o tsv" "Failed to get service principal ID for ACR role assignment")
      log_info "Assigning ACR roles to service principal: $CURRENT_USER_ID"
    fi

    # Assign ACR Push role to the current user
    run_az_command "az role assignment create --assignee '$CURRENT_USER_ID' --role 'AcrPush' --scope '$ACR_ID'" "Failed to assign AcrPush role to current user"
    log_heading "  ✅ Assigned 'AcrPush' on $ACR_NAME to current user"

    # Assign ACR Pull role to the current user
    run_az_command "az role assignment create --assignee '$CURRENT_USER_ID' --role 'AcrPull' --scope '$ACR_ID'" "Failed to assign AcrPull role to current user"
    log_heading "  ✅ Assigned 'AcrPull' on $ACR_NAME to current user"

# ACR Push for Splunk Assets to Container Registry
log_info "Pushing Splunk Operator container image to ACR..."
    run_az_command "az acr import --name '$ACR_NAME' --source $OPERATOR_IMAGE --image $OPERATOR_TAG" "Failed to import Splunk Operator image to ACR"
    log_heading "  ✅ Splunk Operator container image ($OPERATOR_IMAGE) pushed to ACR: $ACR_NAME"

log_info "Pushing Splunk container image to ACR..."
    run_az_command "az acr import --name '$ACR_NAME' --source $SPLUNK_IMAGE --image $SPLUNK_TAG" "Failed to import Splunk image to ACR"

# Waiting for 30 seconds to ensure ACR replication and RBAC propagation
log_info "Waiting 30 seconds..."
sleep 30
log_info "Done waiting."

# Output of container images pushed
log_heading "Container images in ACR '$ACR_NAME':"
  CONTAINER_IMAGES=$(run_az_command "az acr repository list --name '$ACR_NAME' --output tsv" "Failed to list ACR repositories")
  echo "$CONTAINER_IMAGES"

log_heading "✅ Deployment '$DEPLOYMENT_NAME' completed successfully at subscription scope."
