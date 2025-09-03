# Implement CI/CD pipeline to automatically deploy changes
We will expect infrastructure is already deployed including Azure Container App. This can be done in different workflow design for infrastructure. In our solution we will first implement simple workflow to build and push changes and then focus on more controlled approach with manual approval gate and ability to see new version before it is rolled out to all users.

## Simple CI/CD pipeline
We will create GitHub Actions workflow. Make sure Dockerfile is present in ```dotnet``` folder. You can use GitHub Copilot to help you with this, here is example prompt to start with:

```
Create GitHub Actions workflow and place it into .github/workflows/simple.yaml
- Start automatically when changes are made to the `dotnet/` folder in main branch
- Add manual start as alternative
- Build and push Docker image to Azure Container Registry. Name of registry will be provided by repository variable $ACR_NAME.
- Name of Azure Container App is lego-catalog-app
- Name of Resource Group where ACA and ACR is deployed is provided via RESOURCE_GROUP_NAME repository variable.
- Azure Login will be solved using Federated Identity towards Azure User Managed Identity with AZURE_CLIENT_ID, AZURE_TENANT_ID and AZURE_SUBSCRIPTION_ID provided as repository variable.
- Check workflow syntax at #fetch https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
- Use run id container image tag
```

Create managed identity in Azure, give it contributor role to the resource group and federate credentials so github can access it. Point federated credentials to your repo and main branch at this time. You can use Azure Portal or enhance your Bicep template from previous challenges. 

Here is example starting prompt:

```
Modify my main.bicep template to include managed identity that will be used by my GitHub Actions.
- Make this identity contributor in current Resource Group
- Configure identity federation pointing to repository https://github.com/tkubica12/MicroHack-AppInnovation in main branch
- Make repository information parameter, but fill in my details into main.bicepparam
- Document change in README.md file in by bicep folder for ch03
- See docs in #fetch https://learn.microsoft.com/en-us/azure/templates/microsoft.managedidentity/identities?pivots=deployment-language-bicep amd https://learn.microsoft.com/en-us/azure/templates/microsoft.managedidentity/userassignedidentities/federatedidentitycredentials?pivots=deployment-language-bicep
```

Make sure to configure all necessary variables in GitHub repository/Security/Secrets and variables/Actions/Variables including AZURE_CLIENT_ID and AZURE_TENANT_ID of your managed identity, AZURE_SUBSCRIPTION_ID and RESOURCE_GROUP_NAME for the target resource group, and ACR_NAME for the Azure Container Registry name.


