variable "user_index" {
  type        = number
  description = <<EOT
Numeric user index (1..n) aligned with per-user infra module.
Used only for generating deterministic UPN and display name (labuserNNN@domain).
EOT
}

variable "domain" {
  type        = string
  description = <<EOT
Entra ID tenant domain (custom or onmicrosoft.com) appended to generated UPN.
Example: contoso.onmicrosoft.com -> labuser001@contoso.onmicrosoft.com.
Must be non-empty when module is instantiated.
EOT
}

variable "password" {
  type        = string
  sensitive   = true
  description = <<EOT
Password assigned to the created user (lab convenience).
Should meet tenant password policy; not printed in plan/output.
EOT
}
