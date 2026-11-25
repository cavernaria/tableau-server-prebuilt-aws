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
  description = "Command to connect kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.this.name} --alias ${var.name}"
}

output "topology" {
  value = var.topology
}

output "efs_file_system_id" {
  description = "ID of the EFS file system for the bootstrap volume (set only in the multi-node topology)"
  value       = one(aws_efs_file_system.bootstrap[*].id)
}

output "efs_mount_target_ip" {
  description = "IP of the EFS mount target (set only in the multi-node topology)"
  value       = one(aws_efs_mount_target.bootstrap[*].ip_address)
}
