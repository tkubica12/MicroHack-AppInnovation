# Implement CI/CD pipeline to automatically deploy changes

## Goal
In this challenge you will use Github Actions to automate the build and deployment of your application to Azure automatically as code changes are made. New version of application should be first deployed to staging environment so functionality can be tested before showing this to users. In our lab we will not consider dev and testing environments with separate databases so your staging (or sometimes called pre-production) will access the same database. Implement manual sign-off in your pipeline after which new version gets promoted to production instance.

## Actions
- Fork this repository to your GitHub account or organization
- Create GitHub Actions workflow that will detect changes in ```dotnet/``` folder, build container, push to Azure Container Registry new version and trigger deployment to Azure Container Apps
- Enhance this solution to deploy new version in a way that users are still presented with previous one yet there is URL for tester to look into it. After approval in pipeline new version should be rolled to all users.

## Success Criteria
- Application is built and deployed automatically.
- New versions are first deployed not visible to users and wait for approval.

## Solution - Spoilerwarning
[Solution Steps](/solutions/ch03/README.md)
