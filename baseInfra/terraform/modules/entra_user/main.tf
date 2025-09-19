resource "azuread_user" "this" {
  user_principal_name   = local.upn
  display_name          = local.display
  password              = var.password
  force_password_change = false
  mail_nickname         = local.mail_nick
}
