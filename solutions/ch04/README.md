# Monitor application performance with tracing
The application is instrumented with the standard OpenTelemetry SDK and is ready to send traces, metrics, and logs to an OTLP endpoint. We will deploy Azure Application Insights to analyze and visualize these traces.

We could embed an Azure Monitor / Application Insights SDK directly, but to avoid vendor-specific code we use the OpenTelemetry Collector integration in Azure Container Apps to receive standard OTLP signals and forward them to Application Insights.

Azure Container Apps supports an **OpenTelemetry Collector** resource at the environment level. It listens for OTLP data and can export to multiple destinations (including Application Insights). Connection settings are automatically injected into running containers as environment variables.

Since the application already emits telemetry, our focus is enabling the collector via the existing Bicep template. Example Copilot prompt:

```
Add Open Telemetry Collector support to out main.bicep in challenge 04 and point it to Azure Application Insights.
- Read documentation here: #fetch https://learn.microsoft.com/en-us/azure/container-apps/opentelemetry-agents?tabs=bicep%2Carm-example
- Provision Application Insights on top of Log Analytics workspace, see #fetch https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/scenarios-monitoring
```

You may need to create a new revision of the application so it picks up the injected environment variables. No further code changes are required to begin collecting basic telemetry in Application Insights using the open‑source OpenTelemetry exporter.

![](/images/ch04-map.png)


![](/images/ch04-perf.png)