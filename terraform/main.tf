terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.27"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket       = "heartbot-terraform-state-abaig"
    key          = "heartbot/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  lambda_function_name = "${var.project_name}-handler-${var.environment}"

  # Restrict CORS to wildcard only in dev; require explicit origins otherwise.
  effective_cors_origins = var.environment == "dev" ? ["*"] : var.cors_allow_origins

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket" "knowledge_base" {
  bucket        = "${var.project_name}-knowledge-base-${var.environment}"
  force_destroy = true

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "knowledge_base" {
  bucket = aws_s3_bucket.knowledge_base.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "knowledge_base" {
  bucket = aws_s3_bucket.knowledge_base.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "knowledge_base" {
  bucket = aws_s3_bucket.knowledge_base.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Expire non-current versions after 30 days to prevent unbounded storage costs.
resource "aws_s3_bucket_lifecycle_configuration" "knowledge_base" {
  bucket = aws_s3_bucket.knowledge_base.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3vectors_vector_bucket" "heartbot" {
  vector_bucket_name = "${var.project_name}-vectors-${var.environment}"
}

resource "aws_s3vectors_index" "heartbot" {
  index_name         = "${var.project_name}-index"
  vector_bucket_name = aws_s3vectors_vector_bucket.heartbot.vector_bucket_name

  # Titan Embeddings V2 outputs 1024-dimensional float32 vectors.
  data_type       = "float32"
  dimension       = 1024
  distance_metric = "cosine"
}

data "aws_iam_policy_document" "bedrock_kb_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    # Prevent confused-deputy attacks by scoping to this account only.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "bedrock_kb_policy" {
  # Allow Bedrock to invoke the embedding model when ingesting documents.
  statement {
    sid    = "BedrockInvokeEmbeddingModel"
    effect = "Allow"

    actions = ["bedrock:InvokeModel"]

    resources = [
      "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.embedding_model_id}",
    ]
  }

  # Allow Bedrock to read source documents from the ingestion S3 bucket.
  statement {
    sid    = "S3SourceDocAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.knowledge_base.arn,
      "${aws_s3_bucket.knowledge_base.arn}/*",
    ]
  }

  # Allow Bedrock to manage vectors in the S3 Vectors index.
  # Scoped to the specific vector bucket ARN — not "*".
  statement {
    sid    = "S3VectorsAccess"
    effect = "Allow"

    actions = [
      "s3vectors:CreateIndex",
      "s3vectors:DeleteIndex",
      "s3vectors:GetIndex",
      "s3vectors:ListIndexes",
      "s3vectors:PutVectors",
      "s3vectors:GetVectors",
      "s3vectors:DeleteVectors",
      "s3vectors:QueryVectors",
    ]

    resources = [
      aws_s3vectors_vector_bucket.heartbot.vector_bucket_arn,
      "${aws_s3vectors_vector_bucket.heartbot.vector_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_role" "bedrock_kb" {
  name               = "${var.project_name}-bedrock-kb-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.bedrock_kb_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy" "bedrock_kb" {
  name   = "${var.project_name}-bedrock-kb-policy-${var.environment}"
  role   = aws_iam_role.bedrock_kb.id
  policy = data.aws_iam_policy_document.bedrock_kb_policy.json
}

resource "aws_bedrockagent_knowledge_base" "heartbot" {
  name     = "${var.project_name}-kb-${var.environment}"
  role_arn = aws_iam_role.bedrock_kb.arn

  knowledge_base_configuration {
    type = "VECTOR"

    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.embedding_model_id}"

      # Required for S3 Vectors: dimensions and data_type must match the index
      # configured in aws_s3vectors_index above (1024, FLOAT32).
      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions          = 1024
          embedding_data_type = "FLOAT32"
        }
      }
    }
  }

  storage_configuration {
    type = "S3_VECTORS"

    # index_arn is the only required attribute for s3_vectors_configuration.
    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.heartbot.index_arn
    }
  }

  # Ensure the IAM role and policy are fully propagated before creating the KB.
  depends_on = [
    aws_iam_role_policy.bedrock_kb,
  ]

  tags = local.common_tags
}

resource "aws_bedrockagent_data_source" "heartbot" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.heartbot.id
  name              = "${var.project_name}-data-source-${var.environment}"

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn = aws_s3_bucket.knowledge_base.arn
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"
      fixed_size_chunking_configuration {
        max_tokens         = 300
        overlap_percentage = 20
      }
    }
  }
}

resource "aws_bedrock_guardrail" "heartbot" {
  name                      = "${var.project_name}-guardrail-${var.environment}"
  blocked_input_messaging   = "I'm not able to assist with that request. Please ask about cardiac health topics."
  blocked_outputs_messaging = "I'm unable to provide that information. Please consult a qualified healthcare provider."
  description               = "Guardrails for HeartBot — restricts off-topic medical advice, PII, and non-cardiac content."

  sensitive_information_policy_config {
    pii_entities_config {
      action = "ANONYMIZE"
      type   = "NAME"
    }

    pii_entities_config {
      action = "ANONYMIZE"
      type   = "EMAIL"
    }

    pii_entities_config {
      action = "ANONYMIZE"
      type   = "US_SOCIAL_SECURITY_NUMBER"
    }

    pii_entities_config {
      action = "ANONYMIZE"
      type   = "AGE"
    }
  }

  tags = local.common_tags
}

resource "aws_bedrock_guardrail_version" "heartbot" {
  guardrail_arn = aws_bedrock_guardrail.heartbot.guardrail_arn
  description   = "Production version of HeartBot guardrails"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_policy" {
  # CloudWatch log delivery — scoped to this function's log group only.
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.lambda_function_name}:*",
    ]
  }

  # Bedrock operations — scoped to the specific guardrail and knowledge base ARNs.
  statement {
    sid    = "BedrockAccess"
    effect = "Allow"

    actions = [
      "bedrock:RetrieveAndGenerate",
      "bedrock:Retrieve",
      "bedrock:InvokeModel",
      "bedrock:ApplyGuardrail",
    ]

    resources = [
      "arn:aws:bedrock:${var.aws_region}::foundation-model/*",
      aws_bedrock_guardrail.heartbot.guardrail_arn,
      aws_bedrockagent_knowledge_base.heartbot.arn,
    ]
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-lambda-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.project_name}-lambda-policy-${var.environment}"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

data "aws_iam_policy_document" "apigw_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigw_cloudwatch" {
  name               = "${var.project_name}-apigw-cw-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.apigw_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "apigw_cloudwatch" {
  role       = aws_iam_role.apigw_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "heartbot" {
  cloudwatch_role_arn = aws_iam_role.apigw_cloudwatch.arn

  depends_on = [aws_iam_role_policy_attachment.apigw_cloudwatch]
}

data "archive_file" "lambda" {
  type       = "zip"
  source_dir = "${path.module}/../lambda"
  # Written outside terraform/ so the zip is never accidentally committed.
  output_path = "${path.module}/../.build/lambda_package.zip"
}

resource "aws_lambda_function" "heartbot" {
  function_name    = local.lambda_function_name
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      KNOWLEDGE_BASE_ID = aws_bedrockagent_knowledge_base.heartbot.id
      GUARDRAIL_ID      = aws_bedrock_guardrail.heartbot.guardrail_id
      GUARDRAIL_VERSION = aws_bedrock_guardrail_version.heartbot.version
      MODEL_ARN         = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.llm_model_id}"
      ENVIRONMENT       = var.environment
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda,
  ]

  tags = local.common_tags
}

resource "aws_apigatewayv2_api" "heartbot" {
  name          = "${var.project_name}-api-${var.environment}"
  protocol_type = "HTTP"
  description   = "HeartBot API Gateway"

  cors_configuration {
    allow_origins = local.effective_cors_origins
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id             = aws_apigatewayv2_api.heartbot.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.heartbot.invoke_arn
  integration_method = "POST"

  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "chat" {
  api_id    = aws_apigatewayv2_api.heartbot.id
  route_key = "POST /chat"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.heartbot.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
    })
  }

  # Ensure the log group and account-level CW role exist before creating the stage.
  depends_on = [
    aws_cloudwatch_log_group.api_gateway,
    aws_api_gateway_account.heartbot,
  ]

  tags = local.common_tags
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.heartbot.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.heartbot.execution_arn}/*/*"
}

resource "aws_s3_bucket" "frontendbucket" {
  bucket        = "${var.project_name}-frontend-${var.environment}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "frontendblock" {
  bucket = aws_s3_bucket.frontendbucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "frontendversioning" {
  bucket = aws_s3_bucket.frontendbucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontendencryption" {
  bucket = aws_s3_bucket.frontendbucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project_name}-oac-${var.environment}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "frontendpolicy" {
  bucket = aws_s3_bucket.frontendbucket.id
  policy = data.aws_iam_policy_document.frontendpolicydoc.json
}

data "aws_iam_policy_document" "frontendpolicydoc" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject"
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.frontend.arn]
    }

    resources = ["${aws_s3_bucket.frontendbucket.arn}/*"]
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        "type" : "metric",
        "properties" : {
          "title" : "Lambda Invocations",
          "region" : "us-east-1",
          "metrics" : [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.heartbot.function_name]
          ],
          "stat" : "Sum",
          "period" : 300,
          "view" : "timeSeries"
        }
      },
      {
        "type" : "metric",
        "properties" : {
          "title" : "Lambda Errors",
          "region" : "us-east-1",
          "metrics" : [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.heartbot.function_name]
          ],
          "stat" : "Sum",
          "period" : 300,
          "view" : "timeSeries"
        }
      },
      {
        "type" : "metric",
        "properties" : {
          "title" : "Lambda Duration",
          "region" : "us-east-1",
          "metrics" : [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.heartbot.function_name]
          ],
          "stat" : "Average",
          "period" : 300,
          "view" : "timeSeries"
        }
      },
      {
        "type" : "metric",
        "properties" : {
          "title" : "API Gateway 4xx Errors",
          "region" : "us-east-1",
          "metrics" : [
            ["AWS/ApiGateway", "4XXError", "ApiId", aws_apigatewayv2_api.heartbot.id]
          ],
          "stat" : "Sum",
          "period" : 300,
          "view" : "timeSeries"
        }
      }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors-${var.environment}"
  alarm_description   = "Heartbot Lambda Errors Exceeded Threshold"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 5
  evaluation_periods  = 1
  period              = 300
  statistic           = "Sum"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.heartbot.function_name
  }

  alarm_actions = [aws_sns_topic.heartbot_alarms.arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${var.project_name}-lambda-duration-${var.environment}"
  alarm_description   = "Heartbot Lambda Exceeded Duration"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 25000
  evaluation_periods  = 1
  period              = 300
  statistic           = "Average"
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.heartbot.function_name
  }

  alarm_actions = [aws_sns_topic.heartbot_alarms.arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "apigw4xxerrors" {
  alarm_name          = "${var.project_name}-gateway-4xx-errors-${var.environment}"
  alarm_description   = "Heartbot API Gateway Has 4xx Errors"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 10
  evaluation_periods  = 1
  period              = 300
  statistic           = "Sum"
  namespace           = "AWS/ApiGateway"
  metric_name         = "4XXError"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = aws_apigatewayv2_api.heartbot.id
  }

  alarm_actions = [aws_sns_topic.heartbot_alarms.arn]

  tags = local.common_tags
}

resource "aws_sns_topic" "heartbot_alarms" {
  name = "${var.project_name}-alarms-${var.environment}"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "heartbot_alarms_email" {
  topic_arn = aws_sns_topic.heartbot_alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}