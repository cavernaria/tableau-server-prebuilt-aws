output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "region" {
  value = var.region
}

output "secret_names" {
  value = { for k, s in aws_secretsmanager_secret.this : k => s.name }
}

output "update_kubeconfig" {
  description = "kubectl をつなぐためのコマンド"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.this.name} --alias ${var.name}"
}

output "topology" {
  value = var.topology
}

output "efs_file_system_id" {
  description = "bootstrap ボリューム用の EFS の ID（マルチノード構成のときだけ値がある）"
  value       = one(aws_efs_file_system.bootstrap[*].id)
}

output "efs_mount_target_ip" {
  description = "EFS のマウントターゲットの IP（マルチノード構成のときだけ値がある）"
  value       = one(aws_efs_mount_target.bootstrap[*].ip_address)
}
