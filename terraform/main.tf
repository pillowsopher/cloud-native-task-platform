terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = "ap-south-1"
  profile = "uptime-monitor"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "uptime-monitor-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "uptime-monitor-public-1"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "uptime-monitor-igw"
  }
}

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

resource "aws_route_table_association" "public" {
  subnet_id = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

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

resource "aws_instance" "k3s_server" {
  ami = "ami-006f82a1d5a27da54"
  instance_type = "t3.micro"
  key_name = "uptime-monitor-key"
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.main.id]

  tags = {
    Name = "k3s-server"
  }
}

resource "aws_instance" "k3s_agent" {
  ami = "ami-006f82a1d5a27da54"
  instance_type = "t3.micro"
  key_name = "uptime-monitor-key"
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.main.id]

  tags = {
    Name = "k3s-agent"
  }
}
