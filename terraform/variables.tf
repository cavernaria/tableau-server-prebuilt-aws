variable "region" {
  description = "展開先のリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "name" {
  description = "リソース名の接頭辞"
  type        = string
  default     = "tableau-prebuilt"
}

variable "api_allowed_cidrs" {
  description = "EKS の API エンドポイントに接続を許可する送信元 CIDR（検証者の送信元 IP）"
  type        = list(string)

  validation {
    condition     = length(var.api_allowed_cidrs) > 0 && !contains(var.api_allowed_cidrs, "0.0.0.0/0")
    error_message = "送信元を絞ること。0.0.0.0/0 は指定できない。"
  }
}

variable "kubernetes_version" {
  description = "EKS の Kubernetes バージョン"
  type        = string
  default     = "1.36"
}

variable "instance_type" {
  description = "ノードを載せるインスタンスのタイプ（x86_64 のみ）"
  type        = string
  default     = "r6i.4xlarge"
}

variable "vpc_cidr" {
  description = "専用 VPC の CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "topology" {
  description = "Tableau Server の構成。single は単一ノード構成、multi は初期ノード 1 つとワーカー 2 つのマルチノード構成"
  type        = string
  default     = "single"

  validation {
    condition     = contains(["single", "multi"], var.topology)
    error_message = "single か multi を指定すること。"
  }
}

variable "worker_instance_type" {
  description = "ワーカーを載せるインスタンスのタイプ（x86_64 のみ。マルチノード構成のときだけ使う）"
  type        = string
  default     = "r6i.2xlarge"
}

variable "extra_node_tags" {
  description = "ノードのインスタンスとボリュームに追加で付けるタグ（アカウント側の自動停止の対象から外すタグなど）"
  type        = map(string)
  default     = {}
}
