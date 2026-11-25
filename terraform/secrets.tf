# Creates only the containers. The values are set outside Terraform, so they never reach the state.
resource "aws_secretsmanager_secret" "this" {
  for_each = {
    license-key    = "Tableau Server license key"
    admin-password = "Tableau Server initial admin password"
  }

  name                    = "${var.name}/${each.key}"
  description             = each.value
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = 0
}
