terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

  }
  backend "s3" {}
}

provider "aws" {
  region = "ap-south-1"
  profile = "uptime-monitor"
}

# The network everything else lives in
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "uptime-monitor-vpc"
  }
}

# Public subnet the EC2 instances launch into (auto-assigns public IPs)
resource "aws_subnet" "public" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "uptime-monitor-public-1"
  }
}

# Gives the VPC a path to/from the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "uptime-monitor-igw"
  }
}

# Routes 0.0.0.0/0 traffic out through the internet gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "uptime-monitor-public-rt"
  }
}

# Wires the route table above to the actual subnet
resource "aws_route_table_association" "public" {
  subnet_id = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Firewall for both EC2 instances: SSH (me only), HTTP/S (public), and
# k3s's own inter-node ports (API, Flannel VXLAN, kubelet), self-referencing
# so the two instances can always reach each other regardless of my IP
resource "aws_security_group" "main" {
  name = "uptime-monitor-sg"
  description = "Uptime monitor app + SSH access"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "SSH from my IP"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "HTTP"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    description = "k3s API (agent join + ongoing cluster traffic)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Flannel VXLAN (pod networking between nodes)"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
  }

  ingress {
    description = "kubelet"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "uptime-monitor-sg"
  }
}

# k3s control plane node - user_data bootstraps swap (needed on t3.micro)
# and installs k3s as the server on first boot
resource "aws_instance" "k3s_server" {
  ami = "ami-006f82a1d5a27da54"
  instance_type = "t3.micro"
  key_name = "uptime-monitor-key"
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.main.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_ecr.name
    user_data = <<-EOF
    #!/bin/bash
    set -e
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    apt-get update && apt-get install -y unzip
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
    rm -rf /tmp/awscliv2.zip /tmp/aws
    curl -sfL https://get.k3s.io | K3S_TOKEN=${random_password.k3s_token.result} sh -
    EOF

  tags = {
    Name = "k3s-server"
  }
}

# k3s worker node - joins k3s_server using the shared token, retries with
# backoff on its own until the server is reachable (no ordering logic needed)
resource "aws_instance" "k3s_agent" {
  ami = "ami-006f82a1d5a27da54"
  instance_type = "t3.micro"
  key_name = "uptime-monitor-key"
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.main.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_ecr.name
    user_data = <<-EOF
    #!/bin/bash
    set -e
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    curl -sfL https://get.k3s.io | K3S_URL=https://${aws_instance.k3s_server.private_ip}:6443 K3S_TOKEN=${random_password.k3s_token.result} sh -
    EOF

  tags = {
    Name = "k3s-agent"
  }
}

# Image registry for the api service
resource "aws_ecr_repository" "api" {
  name = "uptime-monitor-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Image registry for the worker/beat service
resource "aws_ecr_repository" "worker" {
  name = "uptime-monitor-worker"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Role the EC2 instances assume (via their instance profile) so k3s/kubelet
# can pull images from ECR without any stored credentials on the box
resource "aws_iam_role" "ec2_ecr" {
  name = "uptime-monitor-ec2-ecr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Grants ec2_ecr pull-only access to ECR (push happens from CI, not the node)
resource "aws_iam_role_policy_attachment" "ec2_ecr_readonly" {
  role       = aws_iam_role.ec2_ecr.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# EC2 can only take an IAM role via an instance profile, not the role directly
resource "aws_iam_instance_profile" "ec2_ecr" {
  name = "uptime-monitor-ec2-ecr-profile"
  role = aws_iam_role.ec2_ecr.name
}

# Shared join token for k3s_server/k3s_agent - state-only, never written to
# a tracked file
resource "random_password" "k3s_token" {
  length  = 32
  special = false
}

# Registers GitLab.com as a trusted OIDC identity provider so AWS can verify
# tokens GitLab CI issues, without any stored AWS credentials in GitLab
resource "aws_iam_openid_connect_provider" "gitlab" {
  url             = "https://gitlab.com"
  client_id_list  = ["https://gitlab.com"]
  thumbprint_list = ["a103c5e024f5c88fda2adcf9d3aa4a15dabb9fbc"]
}

# Role our GitLab CI pipeline assumes via OIDC - scoped by condition to only
# this project's main branch, so no other GitLab project/branch can use it
resource "aws_iam_role" "gitlab_ci" {
  name = "uptime-monitor-gitlab-ci-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRoleWithWebIdentity"
        Effect    = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.gitlab.arn
        }
        Condition = {
          StringEquals = {
            "gitlab.com:aud" = "https://gitlab.com"
            "gitlab.com:sub" = "project_path:pillowsopher/cloud-native-uptime-monitor:ref_type:branch:ref:main"
          }
        }
      }
    ]
  })
}

# Lets gitlab_ci actually push images to ECR: log in (GetAuthorizationToken,
# account-wide only) plus the layer/manifest upload actions, scoped to our repos
resource "aws_iam_role_policy" "gitlab_ci_ecr_push" {
  name = "ecr-push"
  role = aws_iam_role.gitlab_ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GetAuthToken"
        Action   = "ecr:GetAuthorizationToken"
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Sid    = "PushImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ]
        Resource = [
          aws_ecr_repository.api.arn,
          aws_ecr_repository.worker.arn,
        ]
      }
    ]
  })
}

# Lets the SSM agent on both instances register with AWS and receive commands,
# so GitLab CI can run deploy commands without SSH/an open inbound port
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_ecr.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Lets gitlab_ci send SSM commands to k3s_server (deploy) and read back the
# result - the actual "remote kubectl apply without SSH" mechanism
resource "aws_iam_role_policy" "gitlab_ci_ssm_deploy" {
  name = "ssm-deploy"
  role = aws_iam_role.gitlab_ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SendCommand"
        Effect = "Allow"
        Action = "ssm:SendCommand"
        Resource = [
          aws_instance.k3s_server.arn,
          "arn:aws:ssm:ap-south-1::document/AWS-RunShellScript",
        ]
      },
      {
        Sid      = "ReadCommandResult"
        Effect   = "Allow"
        Action   = "ssm:GetCommandInvocation"
        Resource = "*"
      }
    ]
  })
}

# Used to make the manifests bucket name globally unique below
data "aws_caller_identity" "current" {}

# Hand-off point for deploy: SSM can run commands but can't copy files, so CI
# uploads rendered manifests here and the SSM command downloads them from here
resource "aws_s3_bucket" "deploy_manifests" {
  bucket = "uptime-monitor-deploy-manifests-${data.aws_caller_identity.current.account_id}"
}

# Lets gitlab_ci upload rendered manifests to the hand-off bucket
resource "aws_iam_role_policy" "gitlab_ci_s3_manifests" {
  name = "s3-deploy-manifests"
  role = aws_iam_role.gitlab_ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PutAndDeleteObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.deploy_manifests.arn}/*"
      },
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.deploy_manifests.arn
      }
    ]
  })
}

# Lets k3s_server download what CI uploaded to the hand-off bucket
resource "aws_iam_role_policy" "ec2_s3_manifests" {
  name = "s3-deploy-manifests-read"
  role = aws_iam_role.ec2_ecr.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GetObjects"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.deploy_manifests.arn}/*"
      },
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.deploy_manifests.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "gitlab_ci_ec2_describe" {
  name = "ec2-describe"
  role = aws_iam_role.gitlab_ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ec2:DescribeInstances"
        Resource = "*"
      }
    ]
  })
}
