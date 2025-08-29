# Base infrastructure
This folder contains base starting Azure infrastructure for MicroHack App Innovation.

Current scope (incremental):
- Subscription level Bicep templates to create `n` user environments each containing:
	- Resource Group (`rg-user<NNN>`)
	- Public IP (`pip-user<NNN>`) used exclusively by Bastion
	- NAT Gateway (`nat-user<NNN>`) with its own Public IP (`pip-nat-user<NNN>`) for outbound internet from private subnet
	- Network Security Group restricting RDP (3389) to VirtualNetwork only (`nsg-user<NNN>`)
	- Virtual Network (`vnet-user<NNN>`) with subnets: `vms` (/24), `AzureBastionSubnet` (/26)
	- Network Interface (`nic-user<NNN>`)
	- Windows Server VM (`vm-user<NNN>`) sized `Standard_B2als_v2` (override via param)
- Naming convention (CAF-aligned): `<abbr>-user<NNN>` zero‑padded starting at 001.
- Defaults: `n=5`, location `westeurope` (override via parameters).

Planned future additions (not yet implemented in this commit): VNET, VM (Windows B-series), custom script extension to install runtime & sample app.

## Bicep structure
Files under `bicep/`:
- `main.bicep` – subscription‑scope entrypoint looping `n` times; passes shared admin credentials.
- `userInfra.bicep` – subscription‑scope module creating only the resource group and invoking a workload module in that RG.
- `workload.bicep` – resource‑group scope module creating Public IP, networking (VNet + subnets), NSG, NIC, VM, and Bastion.

All templates are idempotent; re‑deploying with the same parameters performs no destructive changes. Reducing `n` currently does NOT delete previously created higher index groups (deployment stacks can manage deletion – see below). Names follow `<typeAbbrev>-user###` pattern for clarity.

## Deploy with Azure Deployment Stacks
Azure Deployment Stacks give us lifecycle management (including bulk delete) for all resources a template manages.

Prerequisites (once per subscription):
```pwsh
az login                        # if not already logged in
az account set -s <SUBSCRIPTION_ID_OR_NAME>
```

> If Deployment Stacks is not already enabled in your subscription (generally GA now), you may need to register the feature:
```pwsh
az provider register --namespace Microsoft.Resources
```

### Deploy / Update
From `baseInfra/bicep` folder (contains `main.bicepparam` you can edit):
```pwsh
cd baseInfra/bicep
$stackName = 'microhack-base'
az stack sub create `
	--name $stackName `
	--location swedencentral `
	--parameters main.bicepparam `
	--action-on-unmanage deleteAll `
	--deny-settings-mode none `
    --yes
```
Edit `main.bicepparam` (change n, location, credentials) and rerun to scale or modify. Higher index environments removed from params are deleted due to `--action-on-unmanage deleteAll`.

### What-if (optional)
```pwsh
az deployment sub what-if -l swedencentral -f ./main.bicep -p main.bicepparam
```

### List stack resources
```pwsh
az stack sub show -n $stackName --query "resources[].{Name:name,Type:type}" -o table
```

### Destroy everything managed by the stack
```pwsh
az stack sub delete -n $stackName --yes
```

This performs a clean teardown of all per‑user resource groups & their contents created by the stack (VMs, network, IPs, etc.).

---
Add future infra components by extending `userInfra.bicep` (new modules) or enhancing `workload.bicep` so each user environment stays self‑contained.

## Connect to a VM and run the sample app
Each per‑user environment provisions:
- A Windows Server VM (`vm-user<NNN>`)
- Azure Bastion (using the shared Public IP) for secure RDP in the portal
- A Custom Script Extension that installs Git, .NET SDK 8.0.413, SQL Express, clones this repo, and creates a desktop shortcut to run the app
- A NAT Gateway providing scalable outbound SNAT; the VM NIC has no public IP and egress IP is `pip-nat-user<NNN>` (visible via external services like ifconfig.me)

### Steps
1. In the Azure Portal open the resource group `rg-user<NNN>` you want to use.
2. Open the Bastion resource `bastion-user<NNN>` (or use the Bastion connect button from the VM blade).
3. Click "Connect" (RDP over Bastion) and when prompted use:
	- Username: `azureuser`
	- Password: `Azure12345678`
4. Once the desktop session loads you should see a shortcut named **LegoCatalog App**.
5. Double‑click the shortcut. It will:
	- Launch a PowerShell window
	- Start the app with `dotnet run`
	- Open your default browser to `http://localhost:5000` (give it a few seconds)

If the browser does not open automatically, manually navigate to `http://localhost:5000` in the VM.

### Notes / Troubleshooting
- The provisioning script runs only once (via Custom Script Extension). If you change the script and want to reapply, redeploy the extension (update its settings or remove & redeploy) or run `C:\Apps\LegoCatalog\start-app.ps1` manually.
- The provided credentials are for demo only; rotate them for anything beyond a lab scenario.
- Bastion allows RDP only from within the virtual network; direct public RDP is blocked by NSG design.
