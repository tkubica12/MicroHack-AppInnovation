# ch01: Migrate database, containerize application, deploy to Azure
There are multiple ways to solve this challenge; below is one possible approach.

## Step 1: Use a cloud database
We will not initially modify the application; we leave it running on the local VM but deploy a cloud database and reconfigure the app to use it. For this first iteration we allow access over a public endpoint (we may tighten this later). To achieve cost elasticity we use Azure SQL Database (serverless tier) so the database can auto‑pause when idle and scale compute based on load.

You can deploy the database using the Azure Portal, Azure CLI, Bicep, Terraform, Pulumi, or other methods. In this solution we leverage **GitHub Copilot** to author Infrastructure as Code (IaC) templates using Bicep.

Example prompt to start with:
```
In folder bicep create Bicep template to deploy Azure SQL Database in serverless SKU to Azure. 
- Make sure to whitelist IP of our application and allow public access, IP should be parameter
- Administrator login and password should be parameter and ensure @secure() annotation for password
- Use location that is derived from resource group location
- As name must be unique add some unique string with full resource group ID as seed
- Create main.bicep as well as example bicepparam file
- Check correct syntax at #fetch https://learn.microsoft.com/en-us/azure/templates/microsoft.sql/servers?pivots=deployment-language-bicep
- Read documentation at #fetch https://learn.microsoft.com/en-us/azure/azure-sql/database/serverless-tier-overview?view=azuresql&tabs=general-purpose
- Use database auto-pause after 1 hour and autoscaling between 0.5 and 2 cores
- Write simple README.md to describe how to deploy to your resource group and reference parameters file
```

For the VM source IP check the portal for `pip-nat-<user>`. Because the VM runs in an Azure VNet you could alternatively use a Service Endpoint instead of an IP firewall rule; we keep it IP‑based here to mirror on‑premises scenarios.

Note: In challenge 05 you will introduce stricter security (Private Endpoints, customer‑managed key encryption, Managed Identity, etc.).

Retrieve the connection string, configure the application via environment variables or `appsettings.json`, then start the app from the `dotnet` folder:
`dotnet run --project src/LegoCatalog.App/LegoCatalog.App.csproj`
Remember: environment variables override `appsettings.json`. If you previously ran the start script you might still have `$env:SQL_CONNECTION_STRING` set; either remove it (`Remove-Item env:SQL_CONNECTION_STRING`) to fall back to configuration or update it with the new value.

## Step 2: Package as a Docker container and run locally
Create a Dockerfile to package the application and test it locally (Rancher Desktop, Docker Desktop, dev container, etc.).

The application uses a data folder with seed JSON (auto‑imported if the database is empty) and product images. It is not best practice to bake static content into the container image, so we will mount this folder as a volume.

Use GitHub Copilot to help you create the Dockerfile. Here is example prompt to start with:
```
Create Dockerfile for my dotnet application that is using Razor pages. Currently I simply run it with command dotnet run --project src/LegoCatalog.App/LegoCatalog.App.csproj. 
- I want to use built-in web server capability
- We are building for Linux
- Use multi-stage Dockerfile so we build and publish with SDK version and run on runtime version
- Use .NET version 8
- Place Dockerfile into MicroHack-AppInnovation\dotnet so make sure paths used in Dockerfile are relative to it
- Add example docker CLI commands to README on how to build container and run it with mapped volumes to data folder in this project and by leveraging SQL_CONNECTION_STRING set in env and passed as env into docker
```

[Dockerfile](./Dockerfile) should be placed into the `dotnet/` folder. You typically run the `docker build` from that folder or the repo root depending on how you map volumes.

## Step 3: Create Azure Container Registry and build the container there
Ask GitHub Copilot to add an Azure Container Registry (ACR) to your Bicep template and deploy it.

Here is example starting prompt:
```
Extend current main.bicep file to also create Azure Container Registry resource
- As name must be unique add some unique string with full resource group ID as seed
- Use configurable SKU as parameter, but Basic will be default option
- See Bicep documentation for this resource at #fetch https://learn.microsoft.com/en-us/azure/templates/microsoft.containerregistry/registries?pivots=deployment-language-bicep
- You can also check quickstart #fetch https://learn.microsoft.com/en-us/azure/container-registry/container-registry-get-started-bicep?tabs=CLI
```

After deploying the Bicep template, use the Azure CLI to run an on‑demand ACR build. You can have Copilot generate the command (e.g., “Give me an Azure CLI command for an on‑demand build in ACR for my .NET app named lego-catalog”).

```powershell
# Build in ACR
cd dotnet
$registry = "yourregistryname"
az acr build --registry $registry --image lego-catalog/app:latest .
```

## Step 4: Enable access for Azure services to Azure SQL
For simplicity we deploy the application without VNet integration, so we do not have a predictable outbound IP to whitelist. Therefore we temporarily enable access from all Azure services.

Note: later in challenge 5 for enterprise we will significantly enhance network security and will no longer use any public access to services.

Extend your Bicep template to enable “Allow access to Azure services.” You can use a prompt like:
```
Extend main.bicep to enable Allow access to Azure services feature on Azure SQL. This is done by whitilisting 0.0.0.0 as start and end IP.
```

Deploy changes with Bicep.

## Step 5: Deploy the application into Azure Container Apps
Deploy the container into Azure Container Apps by extending the Bicep template to reference the SQL Database and ACR. Example Copilot prompt:

```
Modify main.bicep to deploy application into Azure Container Apps.
- Make sure to deploy ACA environment with workload profile (v2) and use consumption for out app (note consumption profile has no minimum or maximum count settings).
- App will use environment variable `SQL_CONNECTION_STRING` with the Azure SQL Database connection string
- App needs one volume for the seed JSON file and one for images. Mount Azure Files shares and set `IMAGE_ROOT_PATH` and `SEED_DATA_PATH` accordingly.
- App will use external ingress
- App will scale between 0 and 3 instances based on HTTP scaling
- Name of container image in our ACR is lego-catalog/app:latest
- #fetch Bicep structure from https://learn.microsoft.com/en-us/azure/templates/microsoft.app/managedenvironments?pivots=deployment-language-bicep and https://learn.microsoft.com/en-us/azure/templates/microsoft.app/containerapps?pivots=deployment-language-bicep
- You can check additional examples at #fetch https://learn.microsoft.com/en-us/azure/container-apps/azure-resource-manager-api-spec?tabs=arm-template
- #fetch volumes information at https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts-azure-files?tabs=bash
- Configure RBAC and managed identities so ACA can access ACR for image pull following this guide: #getch https://docs.azure.cn/en-us/container-apps/managed-identity-image-pull?tabs=bash&pivots=bicep
- Size container to 1 cpu and 2GB of RAM
```

Upload the JSON and images to the file shares and test your application.


**That's it! The app is up and running and you are ready for the next challenge.**

## BONUS
We separated static content from the container image, which is good—but even better would be to avoid serving images from the application container at all. As a bonus, investigate changes (if any) needed to **serve images directly from Azure Blob Storage**. With a small base URL change and proper CORS settings you can save container resources and get a more scalable, cost‑effective solution.

Also note that static content can be cached. In challenge 5 (enterprise) when adding **Azure Front Door** for security and performance, you can enable **image caching** to further accelerate delivery.
