output "api_gateway_url" {
  description = "Full /chat endpoint URL — paste this into your .env as API_URL"
  value       = "${aws_apigatewayv2_api.heartbot.api_endpoint}/chat"
}

output "api_gateway_id" {
  description = "ID of the API Gateway HTTP API"
  value       = aws_apigatewayv2_api.heartbot.id
}

output "lambda_function_name" {
  description = "Name of the HeartBot Lambda function"
  value       = aws_lambda_function.heartbot.function_name
}

output "lambda_function_arn" {
  description = "ARN of the HeartBot Lambda function"
  value       = aws_lambda_function.heartbot.arn
}

output "knowledge_base_id" {
  description = "ID of the Bedrock Knowledge Base"
  value       = aws_bedrockagent_knowledge_base.heartbot.id
}

output "knowledge_base_arn" {
  description = "ARN of the Bedrock Knowledge Base"
  value       = aws_bedrockagent_knowledge_base.heartbot.arn
}

output "knowledge_base_data_source_id" {
  description = "ID of the Bedrock Knowledge Base data source — needed for manual sync"
  value       = aws_bedrockagent_data_source.heartbot.data_source_id
}

output "guardrail_id" {
  description = "ID of the Bedrock Guardrail"
  value       = aws_bedrock_guardrail.heartbot.guardrail_id
}

output "guardrail_arn" {
  description = "ARN of the Bedrock Guardrail"
  value       = aws_bedrock_guardrail.heartbot.guardrail_arn
}

output "guardrail_version" {
  description = "Published version of the Bedrock Guardrail"
  value       = aws_bedrock_guardrail_version.heartbot.version
}

output "s3_knowledge_base_bucket" {
  description = "Name of the S3 bucket holding source documents"
  value       = aws_s3_bucket.knowledge_base.bucket
}

output "s3_knowledge_base_bucket_arn" {
  description = "ARN of the S3 bucket holding source documents"
  value       = aws_s3_bucket.knowledge_base.arn
}

output "s3_vectors_bucket_name" {
  description = "Name of the S3 Vectors bucket holding embeddings"
  value       = aws_s3vectors_vector_bucket.heartbot.vector_bucket_name
}

output "s3_vectors_index_arn" {
  description = "ARN of the S3 Vectors index"
  value       = aws_s3vectors_index.heartbot.index_arn
}
