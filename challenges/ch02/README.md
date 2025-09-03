# Test autoscaling under load

## Goal
In this challenge we will put our application under load to make sure auto-scaling work properly. Note this application is using Blazor technology which uses SignalR (WebSockets with fallback to long polling) which might make testing little more challenging.

## Actions
- OPTIONAL: Experience slow-start by decreasing coll-down in Azure Container App to 5 minutes and set auto-pause of SQL to 15 minutes (which is minimum) and wait. Then open browser and measure time for application and database to get started. It takes some time - for what use cases this is viable option?
- Use Azure App Testing to generate load to application including something that generates load on database. When to use Azure Load Testing and when Playwright workspaces? Or combination? Will you use JMeter or Locust or for our situation simple URL test is enough?

## Success Criteria
- Demonstrate Azure Container Apps scaled automatically to multiple replicas and SQL database used more than minimum cores.

## Solution - Spoilerwarning
[Solution Steps](/solutions/ch02/README.md)
