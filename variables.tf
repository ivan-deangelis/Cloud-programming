variable "project" {
  description = "Project name/prefix"
  type        = string
  default     = "demo-aws-app"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "Two public subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "azs" {
  description = "Two AZs in the selected region"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]
}
