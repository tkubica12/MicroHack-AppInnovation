# Challenge 5 (Enterprise Flavor): Implement Security Best Practices

This optional, open-ended challenge is for teams who want to harden the modernized application beyond the core MicroHack outcomes. Focus on applying enterprise-grade security controls across network, identity, data, and perimeter.

Suggested areas to explore:

## 1. Network Isolation
- Place compute components (e.g., container apps, function apps, app service, AKS) inside a Virtual Network where supported.
- Use Private Endpoints for PaaS services such as Azure SQL Database, Storage, or Cognitive Services so traffic stays on the Microsoft backbone.
- Restrict public network access on services once private connectivity is established.

## 2. Secure Ingress
- Introduce Azure Front Door (or Application Gateway + WAF) as the single public entry point with Web Application Firewall enabled (OWASP rules, custom rules for IP allow/deny, bot protection if available).
- Ensure the application backend cannot be accessed directly (lock down origin with private endpoint, service firewall rules, or Front Door origin access restrictions).
- Enforce HTTPS/TLS with minimum TLS version and consider custom domain + managed certificate.

## 3. Identity & Access
- Integrate Entra ID (Azure AD) user authentication for the front-end (OIDC / OAuth2).
- Use Managed Identity for service-to-service and database access instead of secrets (e.g., Azure SQL Database AAD authentication, Storage, Key Vault).
- Centralize secrets in Azure Key Vault; rotate anything that cannot yet use Managed Identity.

## 4. Data Protection
- Evaluate Transparent Data Encryption (TDE) with Customer Managed Key (CMK) in Key Vault for Azure SQL Database.
- Consider double encryption or Always Encrypted (if sensitive columns) and column-level security / row-level security as applicable.
- Enable diagnostic logs and audit trails (SQL auditing to Log Analytics or Storage + Defender for Cloud recommendations).

## 5. Observability & Threat Detection
- Stream WAF logs, Front Door logs, and SQL audit logs to Log Analytics / Sentinel for correlation.
- Enable Defender for Cloud plans relevant to your services and review generated hardening recommendations.

Ask coaches for guidance if you are unsure which path to take—there is no single “correct” solution. Prioritize depth in a few areas over doing everything superficially.

> Tip: Implement changes incrementally; verify each control before moving to the next to avoid troubleshooting compounded issues.