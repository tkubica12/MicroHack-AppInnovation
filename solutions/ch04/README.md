# Monitor application performance with tracing
Our application is instrumented with standard OpenTelemetry SDK and ready so send traces to OTEL endpoint. We need will deploy Azure Application Insights to analyze and visualize these traces.
We could use Azure Monitor exported directly in our code, but order to comply with requirement to not have vendor-specific monitoring SDK in app we will use OTEL collector as part of Azure Container Apps to collect standard traces and convert to format supported by Azure Application Insights.

