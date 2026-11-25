# マルチノード構成の bootstrap ボリューム。初期ノードが書いたブートストラップファイルを、ワーカーが読む。
# Pod が別々のインスタンスに載るので、EBS（1 台にしか付かない）ではなく EFS を使う。
# 単一ノード構成では何も作らない。
locals {
  multi = var.topology == "multi"
}

# ブートストラップファイルはマスターキーストアの複製を含むので、保存時に暗号化する。
resource "aws_efs_file_system" "bootstrap" {
  count = local.multi ? 1 : 0

  encrypted = true

  tags = { Name = "${var.name}-bootstrap" }
}

resource "aws_security_group" "efs" {
  count = local.multi ? 1 : 0

  name        = "${var.name}-efs"
  description = "EFS mount target: NFS from the EKS instances only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-efs" }
}

# マネージドノードグループのインスタンスには、EKS がクラスタのセキュリティグループを付ける。
# NFS（2049 番）は、そのセキュリティグループからだけ受ける。
resource "aws_vpc_security_group_ingress_rule" "efs_nfs" {
  count = local.multi ? 1 : 0

  security_group_id            = aws_security_group.efs[0].id
  referenced_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
}

# インスタンスを置く AZ にだけマウントターゲットを作る。
resource "aws_efs_mount_target" "bootstrap" {
  count = local.multi ? 1 : 0

  file_system_id  = aws_efs_file_system.bootstrap[0].id
  subnet_id       = aws_subnet.private[0].id
  security_groups = [aws_security_group.efs[0].id]
}

resource "aws_iam_role" "efs_csi" {
  count = local.multi ? 1 : 0

  name               = "${var.name}-efs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy_attachment" "efs_csi" {
  count = local.multi ? 1 : 0

  role       = aws_iam_role.efs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}

resource "aws_eks_addon" "efs_csi" {
  count = local.multi ? 1 : 0

  cluster_name = aws_eks_cluster.this.name
  addon_name   = "aws-efs-csi-driver"

  pod_identity_association {
    role_arn        = aws_iam_role.efs_csi[0].arn
    service_account = "efs-csi-controller-sa"
  }

  depends_on = [
    aws_eks_node_group.this,
    aws_eks_node_group.worker,
    aws_eks_addon.pod_identity,
    aws_iam_role_policy_attachment.efs_csi,
  ]
}
