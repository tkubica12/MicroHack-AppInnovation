# Monitor application performance with tracing

## Goal
Our application has been instrumented with standard OpenTelemetry tracing to monitor performance and diagnose issues, yet it is not compiled to support any specific vendor monitoring solution such as Microsoft. Add Azure Application Insights via collector so there is no vendor lock-in on application level.

## Actions
- Ensure application tracing is collected and sent to Azure Application Insights.

## Success Criteria
- In Azure Application Insights, we can see traces from our application.

## Solution - Spoilerwarning
[Solution Steps](/solutions/ch04/README.md)
