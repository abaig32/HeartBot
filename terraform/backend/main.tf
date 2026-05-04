terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.27"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "backendbucket"{
    bucket = "heartbot-terraform-state-abaig"

    lifecycle {
      prevent_destroy = true
    }
}

resource "aws_s3_bucket_public_access_block" "stateblock" {
    bucket = aws_s3_bucket.backendbucket.id

    block_public_acls = true
    block_public_policy = true
    ignore_public_acls = true
    restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backendversioning" {
    bucket = aws_s3_bucket.backendbucket.id

    versioning_configuration {
      status = "Enabled"
    }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backendconfig" {
    bucket = aws_s3_bucket.backendbucket.id

    rule {
        apply_server_side_encryption_by_default {
            sse_algorithm = "aws:kms"
        }
    }
}

resource "aws_s3_bucket_policy" "httpsaccess" {
    bucket = aws_s3_bucket.backendbucket.id
    policy = data.aws_iam_policy_document.onlyallowhttpsaccess.json
}

data "aws_iam_policy_document" "onlyallowhttpsaccess" {
  statement {
    sid    = "DenyNonHTTPS"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.backendbucket.arn,
      "${aws_s3_bucket.backendbucket.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}