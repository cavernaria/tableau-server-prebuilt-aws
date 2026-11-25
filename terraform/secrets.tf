# 入れ物だけを作る。値は Terraform を通さずに入れるので、state には残らない。
resource "aws_secretsmanager_secret" "this" {
  for_each = {
    license-key    = "Tableau Server のライセンスキー"
    admin-password = "Tableau Server の初期管理者のパスワード"
  }

  name                    = "${var.name}/${each.key}"
  description             = each.value
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = 0
}
