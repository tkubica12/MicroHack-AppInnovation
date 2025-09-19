# Implement CI/CD pipeline to automatically deploy changes
We assume the infrastructure (including the Azure Container App) is already deployed. There are multiple possible workflow designs. Here we first implement a simple build + deploy workflow, then evolve it into a controlled promotion model with manual approval and traffic switching between revisions.

## Simple CI/CD pipeline
Create a GitHub Actions workflow. Ensure the Dockerfile is present in the `dotnet` folder. You can use GitHub Copilot to help; example prompt:

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

Create a managed identity in Azure, assign it the Contributor role on the resource group, and configure federated credentials so GitHub can obtain OIDC tokens. Point the federated credential to your repository and `main` branch initially. You can use the Azure Portal or extend your prior Bicep template.

Example starting prompt:

```
Modify my main.bicep template to include managed identity that will be used by my GitHub Actions.
- Make this identity contributor in current Resource Group
- Configure identity federation pointing to repository https://github.com/tkubica12/MicroHack-AppInnovation in main branch
- Make repository information parameter, but fill in my details into main.bicepparam
- Document change in README.md file in by bicep folder for ch03
- See docs in #fetch https://learn.microsoft.com/en-us/azure/templates/microsoft.managedidentity/identities?pivots=deployment-language-bicep amd https://learn.microsoft.com/en-us/azure/templates/microsoft.managedidentity/userassignedidentities/federatedidentitycredentials?pivots=deployment-language-bicep
```

Configure repository variables (Actions > Variables) and/or secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `RESOURCE_GROUP_NAME`, `ACR_NAME`.

## Multi-step pipeline
Now comment out (or delete) the simple workflow and create an advanced version. Enable multiple revision mode in Azure Container Apps to run two versions concurrently. Deploy the new revision without user traffic, test it (optionally route a small percentage), then require a manual approval before promoting it to receive 100% of traffic and deactivating old revisions. Extend the Managed Identity with additional federated credentials for environment-scoped deployments.

Example prompt:

```
Change `main.bicep` in ch03 to enable multiple revisions in Azure Container Apps. Also add two environment-scoped federated credentials (staging, production) for the GitHub managed identity. Federated credentials cannot be configured in parallel—use proper `dependsOn` ordering.
```

Modify the GitHub Actions workflow to support multiple revisions in Azure Container Apps.

Example prompt:

```
Change `.github/workflows/deploy.yaml` to support multiple revisions in Azure Container Apps:
- Deploy new container image as a new revision (no initial traffic).
- Require a manual approval (GitHub Environments) before promotion.
- After approval: shift 100% traffic to the new revision and deactivate previous revisions.
- Use two environments: `staging` and `production`.
```

Configure an approval rule for the `production` environment in GitHub.

![](/images/ch03-env-approval.png)

In the Azure Portal, inspect the new revision, obtain its test URL, and verify the application behavior.

When satisfied, approve the deployment to production in GitHub.

![](/images/ch03-approval.png)