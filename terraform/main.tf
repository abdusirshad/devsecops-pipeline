# ----------------------------------------------------------------------------
# Sample Terraform scanned by the IaC stage (Checkov + Trivy config).
# Hardened S3 bucket + KMS key intended to pass common CIS / Checkov checks:
#   - encryption at rest (KMS, key rotation enabled)
#   - versioning enabled
#   - public access fully blocked
#   - TLS-only bucket policy
# This is illustrative IaC, not applied by CI (no backend / credentials).
# ----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region for sample resources."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Globally-unique name for the artifacts bucket."
  type        = string
  default     = "devsecops-sample-artifacts"
}

resource "aws_kms_key" "artifacts" {
  description             = "CMK for the DevSecOps sample artifacts bucket."
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_s3_bucket" "artifacts" {
  bucket = var.bucket_name

  tags = {
    Project   = "devsecops-pipeline"
    ManagedBy = "terraform"
    Owner     = "md-irshad"
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.artifacts.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "tls_only" {
  bucket = aws_s3_bucket.artifacts.id
  policy = data.aws_iam_policy_document.tls_only.json
}

data "aws_iam_policy_document" "tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

output "bucket_arn" {
  description = "ARN of the artifacts bucket."
  value       = aws_s3_bucket.artifacts.arn
}
