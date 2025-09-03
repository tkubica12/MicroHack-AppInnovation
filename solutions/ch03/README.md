# Implement CI/CD pipeline to automatically deploy changes
We will expect infrastructure is already deployed including Azure Container App. This can be done in different workflow design for infrastructure. In our solution we will first implement simple workflow to build and push changes and then focus on more controlled approach with manual approval gate and ability to see new version before it is rolled out to all users.

## Simple CI/CD pipeline
We will create GitHub Actions workflow. Make sure Dockerfile is present in ```dotnet``` folder. You can use GitHub Copilot to help you with this, here is example prompt to start with:

```
Create GitHub Actions workflow and place it into .github/workflows/deploy.yaml
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

## Multi-step pipeline
In this step we will comment-out simple pipeline and create new more advanced version. We will change revision mode in Azure Container Apps to support multiple versions running int the same time, deploy new version without sending user traffic to it, do manual testing (or send small fraction of users to new version) and have manual step in our GitHub Actions workflow to promote new version to be only active revision in Azure Container App and change Managed Identity for GitHub to support multiple environments.

Example prompt:

```
Change main.bicep in ch03 to enable multiple revision in Azure Container Apps. Also we will change Managed Identity for GitHub to support multiple environments. Implement another two federated credentials of type environment and values staging and production. Note federated credentials cannot be configured in paralel so add proper dependsOn.
```

Let's modify GitHub Actions workflow to support multiple revisions in Azure Container Apps.

Here is example prompt:

```
Change .github/workflows/deploy.yaml to support multiple revisions in Azure Container Apps
- Changes in container should be deployed into Azure Container App which is in multiple mode for revision so it is deployed yet not active for users.
- After this manual approval must be done in pipeline to continue
- After approval new revision should receive 100% of traffic and previous revision should be deactivated.
- You can use environment feature with approval to implement this, there are two environments: staging and production.
```

You will also need to configure approval to deploy to production environment in GitHub.

![](/images/ch03-env-approval.png)

Now look into Azure Portal to check new revision. Click on it, get its url, see how application it works.

If you are ready go to GitHub and approve the deployment to production.

![](/images/ch03-approval.png)