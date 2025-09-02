# Test autoscaling under load

Azure App Testing compes with two different styles of application testing. Azure Load Testing service supports simple URL tests, JMeter or Lucost advanced test scenarios and can be used to automate complex sequences of API calls. But as time of this writing (Seoptember 2025) it does not support WebSockets so while we can use it to test scaling of our Azure Container Apps, this will not generate load on our database as such functionality is provided via WebSocket channel. Second service is Playwright Workspace which is not use fo API testing, but for web browser automation and as such can establish full end-user experience including WebSocket. But this service is rather used for functionality testing, not performance.

In our solution we are going to leverage simple URL testing and the fact that application has already be prepared with testing API exactly for purpose of testing access to database. Due to this decision in our application we can use API testing even with Blazor based application.

Note: perf testing frameworks are introducing WebSocket support via plug-in. At this point those Lucost plugins are not supported in Azure Load Testing Service, but might be in a future.

## Solution
1. Deploy Azure App Testing via Azure Portal
2. Create Load Testing test in simple URL-based mode
3. Generate two types of requests - GET to the main page and GET to our testing path /perftest/catalog with headers x-api-key = Azure12345678
4. Check number of replicas in Azure Container App increases when testing runs
5. Check metric App CPU Billed on SQL Database to see increase in consumed vCore. Note this metric is in vCore seconds - switch graph to 1 minute granularity where value 30 coresponds to 0.5 vCore, value 60 to 1 vCore, value 120 to 2 vCore and so on.