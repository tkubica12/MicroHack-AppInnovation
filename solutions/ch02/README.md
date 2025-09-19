# Test autoscaling under load

Azure offers two complementary approaches to application load and functional testing:

1. **Azure Load Testing** – Supports simple URL tests, JMeter scripts, and (via open source) Locust scenarios to automate complex API sequences. As of September 2025 it does **not** support WebSockets. Therefore, while we can use it to test scaling of Azure Container Apps, it will not exercise Blazor Server's real‑time (WebSocket) data channel.
2. **Playwright Testing (Workspace)** – Designed for browser automation (end‑to‑end functional flows). It can establish WebSocket connections but is not optimized for sustained high‑throughput performance load.

Because our application includes a dedicated performance testing endpoint that queries the database over standard HTTP, we can rely on simple URL-based load tests to drive representative database + serialization load without WebSocket support.

Note: Some performance frameworks are adding WebSocket support through plugins. At this time the relevant Locust WebSocket plugins are not supported within Azure Load Testing managed service, but this may change.

## Solution
1. Deploy Azure Load Testing via the Azure Portal.
2. Create a URL-based test.
3. Configure two request types:
	- `GET /` (main page)
	- `GET /perftest/catalog` with header `x-api-key: Azure12345678`
4. Observe the replica count of the Azure Container App increasing during the run (HTTP-based scaling rule).
5. Monitor the Azure SQL Database metric **App CPU Billed**. This metric is in vCore-seconds; at 1‑minute granularity a value of 30 ≈ 0.5 vCore, 60 ≈ 1 vCore, 120 ≈ 2 vCores.