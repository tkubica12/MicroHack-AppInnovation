#!/bin/bash

# Script to delete all resource groups in the current Azure subscription
# This script will:
# 1. List all resource groups
# 2. Remove any locks from each resource group
# 3. Delete all resource groups with auto-confirmation and without waiting

set -e

echo "Starting resource group cleanup..."
echo "Current subscription:"
az account show --query "{Name:name, SubscriptionId:id}" -o table
echo ""

# Get all resource groups
echo "Fetching all resource groups..."
resource_groups=$(az group list --query "[].name" -o tsv)

if [ -z "$resource_groups" ]; then
    echo "No resource groups found."
    exit 0
fi

echo "Found the following resource groups:"
echo "$resource_groups"
echo ""

# Process each resource group
for rg in $resource_groups; do
    echo "Processing resource group: $rg"
    
    # Check and remove locks
    echo "  Checking for locks..."
    locks=$(az lock list --resource-group "$rg" --query "[].id" -o tsv)
    
    if [ -n "$locks" ]; then
        echo "  Found locks, removing..."
        while IFS= read -r lock_id; do
            echo "    Removing lock: $lock_id"
            az lock delete --ids "$lock_id" || echo "    Warning: Failed to delete lock $lock_id"
        done <<< "$locks"
    else
        echo "  No locks found."
    fi
    
    # Delete resource group without waiting
    echo "  Deleting resource group $rg (no-wait)..."
    az group delete --name "$rg" --yes --no-wait || echo "  Warning: Failed to initiate deletion for $rg"
    echo ""
done

echo "All resource group deletions have been initiated."
echo "Note: Deletions are running in the background (--no-wait flag used)."
echo "You can monitor progress with: az group list -o table"
