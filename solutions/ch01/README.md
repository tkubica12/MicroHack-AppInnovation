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
