# ch01: Migrate database, containerize application, deploy to Azure
There are more ways how to solve this challenge. Here is one possible approach.

## Step 1: use cloud database
We will not initially touch application and leave it as is in local VM, but deploy cloud database and reconfigure application to use it. For that we will use access over public endpoint (this is something we might change in later challenges). In order to have scalable costs we will use Azure SQL Database in serverless SKU so database is able to go sleep when there are no users and scale its performance depending on actual load.

You can deploy database using Azure Portal, Azure CLI, Bicep, Terraform, Pulumi and other methods. In our solution we leverage help of **GitHub Copilot** to author the necessary infrastructure as code (IaC) templates using Bicep.

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

For VM source IP check portal for ```pip-nat-<user>```. Note that since VM runs in Azure VNET you can also easily use Service Endpoint feature on database rather than whitelisting IP, but in this solution we keep it IP based so you can do the same for apps running in on-premises environments.

Note: in challenge 05 you will work on stricter security with Private Endpoint, BYOK encryption, Managed Identity and so on.

Get connection string, configure your application via environmental variables or in ```appsetings.json``` file and start app in dotenet folder with ```dotnet run --project src/LegoCatalog.App/LegoCatalog.App.csproj```. Remember - env overrides ```appsettings.json``` so if you have already run start script yu might have ```$env:SQL_CONNECTION_STRING``` set either remove it (```Remove-Item env:SQL_CONNECTION_STRING```) and use ```appsetings.json``` or set it via env.

## Step 2: Package as Docker container and run locally
In this step we will create Dockerfile to package application and test it locally with Rancher desktop.

Note that application uses data folder with startup JSON data (autoimported to database if empty) and product images. It is not best practice to put static content into Docker image so we will mount this folder as a volume in Docker.

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

[Dockerfile](./Dockerfile) should placed into ```dotnet/``` folder for build, for run you would tycali run from root (depending on how you do volume mapping).

## Step 3: Create Azure Container Registry and use task to build container there
First ask GitHub Copilot to add Azure Container Registry into your Bicep template and deploy it.

Here is example starting prompt:
```
Extend current main.bicep file to also create Azure Container Registry resource
- As name must be unique add some unique string with full resource group ID as seed
- Use configurable SKU as parameter, but Basic will be default option
- See Bicep documentation for this resource at #fetch https://learn.microsoft.com/en-us/azure/templates/microsoft.containerregistry/registries?pivots=deployment-language-bicep
- You can also check quickstart #fetch https://learn.microsoft.com/en-us/azure/container-registry/container-registry-get-started-bicep?tabs=CLI
```

After you deploy Bicep template use Azure CLI to run build task in Azure Container Registry. You can use Ask mode in Github Copilot to write it for you with prompt similar to ```Give me Azure CLI command to use on-demand build for my dotnet application in Azure Container Registry under name lego-catalog.```.

```powershell
# Build in ACR
cd dotnet
$registry = "yourregistryname"
az acr build --registry $registry --image lego-catalog/app:latest .
```

## Step 4: Enable access for Azure services to Azure SQL
For simplicity we will deploy our application without VNET integration so we will not have predictable IP to add into our Azure SQL whitelist. Therefore we will enable access from all Azure services.

Note: later in challenge 5 for enterprise we will significantly enhance network security and will no longer use any public access to services.

Extend your Bicep template with Allow access to Azure services, you can use this prompt to start with:
```
Extend main.bicep to enable Allow access to Azure services feature on Azure SQL. This is done by whitilisting 0.0.0.0 as start and end IP.
```

Deploy changes with Bicep.

## Step 5: Deploy application into Azure Container Apps
We will deploy our application container into Azure Container Apps platform by authoring Bicep template that takes SQL and ACR as references. Here is GitHub Copilot prompt to start with:

```
Modify main.bicep to deploy application into Azure Container Apps.
- Make sure to deploy ACA environment with workload profile (v2) and use consumption for out app (note consumption profile has no minimum or maximum count settings).
- App will user env variable SQL_CONNECTION_STRING where you should put connection string to our Azure SQL Database
- App need to have volume with JSON file and volume with images. Map Azure Files into container as volume and make sure to set env variables IMAGE_ROOT_PATH and SEED_DATA_PATH accordingly.
- App will use Ingress accessible from Internet
- App will scale between 0 and 3 instances based on http-scale
- Name of container image in our ACR is lego-catalog/app:latest
- #fetch Bicep structure from https://learn.microsoft.com/en-us/azure/templates/microsoft.app/managedenvironments?pivots=deployment-language-bicep and https://learn.microsoft.com/en-us/azure/templates/microsoft.app/containerapps?pivots=deployment-language-bicep
- You can check additional examples at #fetch https://learn.microsoft.com/en-us/azure/container-apps/azure-resource-manager-api-spec?tabs=arm-template
- #fetch volumes information at https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts-azure-files?tabs=bash
- Configure RBAC and managed identities so ACA can access ACR for image pull following this guide: #getch https://docs.azure.cn/en-us/container-apps/managed-identity-image-pull?tabs=bash&pivots=bicep
- Size container to 1 cpu and 2GB of RAM
```

Upload JSON and images to your shares and test your application.


**That's it! Our app is now up and running, we are ready for next challenge.**

## BONUS
We have separated static content from container image, which is good, but even better would be to not serve images from our container at all! As bonus activity you might investigate what changes would be needed (if any) in your application to **serve images directly from Azure Blob Storage**. With little bit of base url change and proper CORS settings you can save a lot of your container resources and get cheaper and mora scalable solution.

Also note that static content can be cached. Think about it if you will do challange 5 enterprise where we add **Azure Front Door** in front of our application to enhance security and performance - there you can turn on **image caching** to speed things up even more!
