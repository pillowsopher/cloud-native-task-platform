output "k3s_server_public_ip" {
  value = aws_instance.k3s_server.public_ip
}

output "k3s_agent_public_ip" {
  value = aws_instance.k3s_agent.public_ip
}

output "ecr_api_repo_url" {
  value = aws_ecr_repository.api.repository_url
}

output "ecr_worker_repo_url" {
  value = aws_ecr_repository.worker.repository_url
}

output "notifications_queue_url" {
  value = aws_sqs_queue.notifications.url
}

output "notifications_table_name" {
  value = aws_dynamodb_table.notifications.name
}

output "lambda_function_name" {
  value = aws_lambda_function.notification_dispatcher.function_name
}
