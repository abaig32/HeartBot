variable "aws_region" {
  description = "AWS region to deploy HeartBot infrastructure"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name prefix for all HeartBot resources"
  type        = string
  default     = "heartbot"
}

variable "llm_model_id" {
  description = "Amazon Bedrock foundation model ID for response generation"
  type        = string
  default     = "amazon.nova-micro-v1:0"
}

variable "embedding_model_id" {
  description = "Amazon Bedrock embedding model ID for knowledge base vectorization"
  type        = string
  # Must output 1024-dimensional FLOAT32 vectors to match aws_s3vectors_index.
  default = "amazon.titan-embed-text-v2:0"
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch log groups"
  type        = number
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch Logs retention period."
  }
}

variable "cors_allow_origins" {
  description = <<-EOT
    Allowed origins for API Gateway CORS.
    In dev this is overridden to ["*"] automatically.
    For staging/prod, set this to your Streamlit app URL, e.g. ["https://your-app.example.com"].
  EOT
  type        = list(string)
  default     = ["*"]
}

variable "alarm_email" {
  description = "Email address to receive CloudWatch alarm notifications"
  type        = string
}