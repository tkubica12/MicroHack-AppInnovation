# Monitor application performance with tracing
Our application is instrumented with standard OpenTelemetry SDK and ready so send traces to OTEL endpoint. We need will deploy Azure Application Insights to analyze and visualize these traces.

We could use Azure Monitor exported directly in our code, but order to comply with requirement to not have vendor-specific monitoring SDK in app we will use OTEL collector as part of Azure Container Apps to collect standard traces and convert to format supported by Azure Application Insights.

Azure Container Apps support **Open Telemetry Collector** as a service. This gets deployed into environment and listens for OTEL messages and can be configured with multiple backends including **Azure Application Insights**. Connection settings are automatically injected into running containers.

As application is ready focus on configuring Azure Container Apps. We will use our Bicep template from previous challenge. Here is example GitHub Copilot prompt to start with:

```
Add Open Telemetry Collector support to out main.bicep in challenge 04 and point it to Azure Application Insights.
- Read documentation here: #fetch https://learn.microsoft.com/en-us/azure/container-apps/opentelemetry-agents?tabs=bicep%2Carm-example
- Provision Application Insights on top of Log Analytics workspace, see #fetch https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/scenarios-monitoring
```

You might need to create new revision of our application for it to get injected env variables, but there is nothing else needed to start collecting basic telemetry into Aplication Insights using standard open source OpenTelemetry exporter without any Microsoft-specific SDK.

![](/images/ch04-map.png)


![](/images/ch04-perf.png)