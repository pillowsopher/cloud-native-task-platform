terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source = "hashicorp/archive"
      version = "~> 2.4"
    }

  }

  backend "s3" {}
}

provider "aws" {
  region = "ap-south-1"
  profile = "uptime-monitor"
}

resource "aws_sqs_queue" "notifications" {
  name = "uptime-monitor-notifications"
  message_retention_seconds = 86400
  redrive_policy = jsonencode({
  deadLetterTargetArn = aws_sqs_queue.notifications_dlq.arn
  maxReceiveCount = 3
  })

}

resource "aws_dynamodb_table" "notifications" {
  name = "uptime-monitor-notifications"
  billing_mode = "PAY_PER_REQUEST"
  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

data "archive_file" "notifications_lambda" {
  type = "zip"
  source_dir = "${path.module}/../../lambda/notifications"
  output_path = "${path.module}/notifications.zip"
}

resource "aws_iam_role" "lambda_notifications" {
  name = "uptime-monitor-lambda-notifications-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_sqs_execution" {
  role = aws_iam_role.lambda_notifications.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

resource "aws_iam_role_policy" "lambda_dynamodb_write" {
  name = "uptime-monitor-lambda-dynamodb-write"
  role = aws_iam_role.lambda_notifications.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "dynamodb:PutItem"
        Effect = "Allow"
        Resource = aws_dynamodb_table.notifications.arn
      }
    ]
  })
}

resource "aws_lambda_function" "notifications" {
  function_name = "uptime-monitor-notifications"
  role = aws_iam_role.lambda_notifications.arn
  handler = "handler.handler"
  runtime = "python3.12"
  filename = data.archive_file.notifications_lambda.output_path
  source_code_hash = data.archive_file.notifications_lambda.output_base64sha256
  timeout = 10
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.notifications.arn
  function_name = aws_lambda_function.notifications.arn
  batch_size = 1
}

resource "aws_sqs_queue" "notifications_dlq" {
  name                      = "uptime-monitor-notifications-dlq"
  message_retention_seconds = 1209600
}

data "aws_iam_role" "ec2_ecr" {
  name = "uptime-monitor-ec2-ecr-role"
}

resource "aws_iam_role_policy" "ec2_sqs_send" {
  name = "uptime-monitor-ec2-sqs-send"
  role = data.aws_iam_role.ec2_ecr.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sqs:SendMessage", "sqs:GetQueueUrl"]
        Effect = "Allow"
        Resource = aws_sqs_queue.notifications.arn
      }
    ]
  })
}

