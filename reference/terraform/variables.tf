variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for naming resources"
  type        = string
  default     = "task-platform"
}

variable "instance_type" {
  description = "EC2 instance type for k3s nodes. t2.micro/t3.micro are free-tier eligible."
  type        = string
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name for SSH access"
  type        = string
}

variable "ssh_ingress_cidr" {
  description = "CIDR allowed to SSH into the nodes — lock this to your own IP/32, not 0.0.0.0/0"
  type        = string
}
