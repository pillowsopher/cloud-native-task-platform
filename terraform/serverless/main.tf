terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region  = "ap-south-1"
  profile = "uptime-monitor"
}

resource "aws_sqs_queue" "notifications" {
  name                      = "uptime-monitor-notifications"
  message_retention_seconds = 86400
}

resource "aws_dynamodb_table" "notifications" {
  name         = "uptime-monitor-notifications"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}
