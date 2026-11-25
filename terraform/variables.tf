variable "region" {
  description = "Region to deploy to"
  type        = string
  default     = "ap-northeast-1"
}

variable "name" {
  description = "Prefix for resource names"
  type        = string
  default     = "tableau-prebuilt"
}

variable "api_allowed_cidrs" {
  description = "Source CIDRs allowed to reach the EKS API endpoint (your own source IP)"
  type        = list(string)

  validation {
    condition = length(var.api_allowed_cidrs) > 0 && alltrue([
      for cidr in var.api_allowed_cidrs : can(cidrhost(cidr, 0)) && try(tonumber(split("/", cidr)[1]), 0) >= 8
    ])
    error_message = "Restrict the source. Each entry must be a valid CIDR with a prefix length of /8 or longer."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.36"
}

variable "instance_type" {
  description = "Instance type that runs the initial node (x86_64 only)"
  type        = string
  default     = "r6i.4xlarge"
}

variable "vpc_cidr" {
  description = "CIDR of the dedicated VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "topology" {
  description = "Tableau Server topology. single is the single-node topology; multi is the multi-node topology with one initial node and two workers"
  type        = string
  default     = "single"

  validation {
    condition     = contains(["single", "multi"], var.topology)
    error_message = "Must be single or multi."
  }
}

variable "worker_instance_type" {
  description = "Instance type for the workers (x86_64 only; used only in the multi-node topology)"
  type        = string
  default     = "r6i.2xlarge"
}

variable "extra_node_tags" {
  description = "Extra tags for the EC2 instances and their volumes (for example, a tag that opts out of an account-level scheduled stop)"
  type        = map(string)
  default     = {}
}
