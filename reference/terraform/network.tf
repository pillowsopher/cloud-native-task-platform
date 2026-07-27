# Uses the account's default VPC/subnet to avoid NAT Gateway costs (NAT
# Gateways are NOT free-tier eligible). For a "real" enterprise setup you'd
# build a dedicated VPC with public/private subnets — documented here as a
# deliberate cost tradeoff, another good interview talking point.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "k3s_nodes" {
  name        = "${var.project_name}-k3s-nodes"
  description = "Security group for k3s server/agent EC2 nodes"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }

  ingress {
    description = "HTTP (Traefik ingress)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "k3s API + node-to-node traffic within the SG"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-k3s-nodes"
  }
}
