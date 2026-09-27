# Disposable prerequisites for the integration suites. The module under test
# needs three things from the account that it deliberately does not create:
#
#   * a pre-existing central S3 access-log bucket (ADR 0008: owned by Log Archive),
#     so this fixture creates a throwaway one that allows S3 server access log
#     delivery;
#   * at least two IAM role ARNs for state access (the CI and break-glass roles).
#     One is the role this suite runs as, resolved from the caller identity: it
#     must be a state access principal and a key administrator, because the module's
#     bucket policy denies every other principal and its key policy has no
#     account-root statement, so the identity that applies it must be named in
#     both. The other is a throwaway stand-in role created here;
#   * globally unique names, from a random suffix.
#
# The suite must run as an IAM role (an assumed-role session): the module accepts
# role ARNs only. Nothing here is a deployable pattern; it is excluded from policy
# scanning (.checkov.yml, trivy.yaml).

resource "random_id" "suffix" {
  byte_length = 4
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

# Resolves the IAM role behind an assumed-role session. Fails the suite early, with
# the module's own role-ARN validation message, when it runs as a plain user.
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
  prefix          = "${var.name_prefix}-${random_id.suffix.hex}"
  partition       = data.aws_partition.current.partition
  account_id      = data.aws_caller_identity.current.account_id
  caller_role_arn = data.aws_iam_session_context.current.issuer_arn

  state_bucket_name = "${local.prefix}-smoke-tfstate"
  log_bucket_name   = "${local.prefix}-logs"

  tags = merge(var.tags, {
    IntegrationTest = "aws.modules.state"
    Disposable      = "true"
  })
}

# ---------------------------------------------------------------------------
# Throwaway central access-log bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "logs" {
  bucket        = local.log_bucket_name
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# S3 server access log delivery supports only SSE-S3 on the destination bucket.
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "S3ServerAccessLogsPolicy"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs.arn}/*"
        Condition = {
          ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:s3:::${local.prefix}-*" }
          StringEquals = { "aws:SourceAccount" = local.account_id }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.logs]
}

# ---------------------------------------------------------------------------
# Throwaway stand-in for the break-glass role
# ---------------------------------------------------------------------------

resource "aws_iam_role" "break_glass" {
  name = "${local.prefix}-break-glass"
  tags = local.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = local.caller_role_arn }
        Action    = "sts:AssumeRole"
      },
    ]
  })
}
