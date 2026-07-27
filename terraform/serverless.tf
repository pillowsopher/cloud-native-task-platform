# Serverless notification path: SQS -> Lambda -> DynamoDB.
# Lambda deployment package itself is built/pushed by GitLab CI (see
# lambda/notification-dispatcher); this just wires the AWS resources.

resource "aws_sqs_queue" "notifications" {
  name                       = "${var.project_name}-notifications"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400
}

resource "aws_dynamodb_table" "notifications" {
  name         = "${var.project_name}-notifications"
  billing_mode = "PAY_PER_REQUEST" # free-tier friendly: no capacity to over-provision
  hash_key     = "notification_id"

  attribute {
    name = "notification_id"
    type = "S"
  }
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "notification_lambda" {
  name               = "${var.project_name}-notification-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  role       = aws_iam_role.notification_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem"]
    resources = [aws_dynamodb_table.notifications.arn]
  }
  statement {
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.notifications.arn]
  }
  statement {
    actions   = ["ses:SendEmail"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name   = "${var.project_name}-notification-lambda-permissions"
  role   = aws_iam_role.notification_lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

# The function itself is deployed by CI (via `aws lambda update-function-code`
# or SAM); this placeholder keeps `terraform apply` self-contained on a fresh
# account. CI overwrites the code after the first apply.
resource "aws_lambda_function" "notification_dispatcher" {
  function_name = "${var.project_name}-notification-dispatcher"
  role          = aws_iam_role.notification_lambda.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  filename      = "${path.module}/../lambda/notification-dispatcher/placeholder.zip"
  timeout       = 10
  memory_size   = 128

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.notifications.name
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.notifications.arn
  function_name    = aws_lambda_function.notification_dispatcher.arn
  batch_size       = 5
}
