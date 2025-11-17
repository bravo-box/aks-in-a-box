#!/bin/bash

read -rp "Provide a name for the Resource Group: " RESOURCE_GROUP_NAME
while [[ -z "$RESOURCE_GROUP_NAME" ]]; do
    read -rp "RESOURCE_GROUP_NAME cannot be empty. Please enter a valid RESOURCE_GROUP_NAME: " RESOURCE_GROUP_NAME
done

read -rp "Provide a name for the Virtual Network: " VNET_NAME
while [[ -z "$VNET_NAME" ]]; do
    read -rp "VNET_NAME cannot be empty. Please enter a valid VNET_NAME: " VNET_NAME
done

read -rp "Provide an address prefix for the VNet (e.g., 10.0.0.0/16): " ADDRESS_PREFIX
while [[ -z "$ADDRESS_PREFIX" ]]; do
    read -rp "ADDRESS_PREFIX cannot be empty. Please enter a valid ADDRESS_PREFIX: " ADDRESS_PREFIX
done

read -rp "Provide a location for the Virtual Network: " LOCATION
while [[ -z "$LOCATION" ]]; do
    read -rp "LOCATION cannot be empty. Please enter a valid LOCATION: " LOCATION
done

echo "Creating Resource Group..."
OUTPUT=$(az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    RESOURCE_ID=$(echo "$OUTPUT" | jq -r '.id')
    echo "✓ Resource group created successfully!"
    echo "Resource ID: $RESOURCE_ID"
else
    echo "✗ Failed to create resource group."
    echo "$OUTPUT"
    exit 1
fi

# Capture the output of the virtual network creation
echo "Creating Virtual Network..."
OUTPUT=$(az network vnet create --name "$VNET_NAME" --resource-group "$RESOURCE_GROUP_NAME" --address-prefix "$ADDRESS_PREFIX" --location "$LOCATION" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    RESOURCE_ID=$(echo "$OUTPUT" | jq -r '.newVNet.id')
    echo "✓ Virtual network created successfully!"
    echo "Resource ID: $RESOURCE_ID"
    
    # Prompt for bastion deployment
    while true; do
        read -rp "Do you wish to deploy bastion attached to this vnet? (y/n): " DEPLOY_BASTION
        DEPLOY_BASTION=$(echo "$DEPLOY_BASTION" | tr '[:upper:]' '[:lower:]')
        if [[ "$DEPLOY_BASTION" =~ ^[yn]$ ]]; then
            break
        else
            echo "Invalid input. Please enter 'y' or 'n'."
        fi
    done
    
    if [[ "$DEPLOY_BASTION" == "y" ]]; then
        read -rp "Provide a name for the Bastion Host: " BASTION_NAME
        while [[ -z "$BASTION_NAME" ]]; do
            read -rp "BASTION_NAME cannot be empty. Please enter a valid BASTION_NAME: " BASTION_NAME
        done
        
        read -rp "Provide a name for the Public IP Address: " PUBLIC_IP_NAME
        while [[ -z "$PUBLIC_IP_NAME" ]]; do
            read -rp "PUBLIC_IP_NAME cannot be empty. Please enter a valid PUBLIC_IP_NAME: " PUBLIC_IP_NAME
        done
        
        echo "Creating bastion host..."
        BASTION_OUTPUT=$(az network bastion create \
            --location "$LOCATION" \
            --name "$BASTION_NAME" \
            --public-ip-address "$PUBLIC_IP_NAME" \
            --resource-group "$RESOURCE_GROUP_NAME" \
            --vnet-name "$VNET_NAME" \
            --sku Standard 2>&1)
        BASTION_EXIT_CODE=$?
        
        if [ $BASTION_EXIT_CODE -eq 0 ]; then
            BASTION_RESOURCE_ID=$(echo "$BASTION_OUTPUT" | jq -r '.id')
            echo "✓ Bastion host created successfully!"
            echo "Bastion Resource ID: $BASTION_RESOURCE_ID"
        else
            echo "✗ Failed to create bastion host."
            echo "$BASTION_OUTPUT"
        fi
    fi
else
    echo "✗ Failed to create virtual network."
    echo "$OUTPUT"
    exit 1
fi
