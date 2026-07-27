data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "random_password" "k3s_token" {
  length  = 32
  special = false
}

# Single control-plane node. A second t3.micro is added as a worker below —
# together they still fit comfortably in EC2 free-tier hours (750 hrs/mo
# covers one instance running 24/7; running two half the month, or both
# during interview-demo windows, keeps you within the free tier).
resource "aws_instance" "k3s_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.k3s_nodes.id]
  iam_instance_profile   = aws_iam_instance_profile.k3s_node.name

  user_data = templatefile("${path.module}/scripts/install-k3s-server.sh", {
    k3s_token = random_password.k3s_token.result
  })

  tags = {
    Name = "${var.project_name}-k3s-server"
  }
}

resource "aws_instance" "k3s_agent" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.k3s_nodes.id]
  iam_instance_profile   = aws_iam_instance_profile.k3s_node.name
  depends_on             = [aws_instance.k3s_server]

  user_data = templatefile("${path.module}/scripts/install-k3s-agent.sh", {
    k3s_token         = random_password.k3s_token.result
    server_private_ip = aws_instance.k3s_server.private_ip
  })

  tags = {
    Name = "${var.project_name}-k3s-agent"
  }
}
