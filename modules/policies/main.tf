# Renders every policy document of the state backend from ARN strings. This
# module creates no resources and declares no provider: it exists so the
# security-critical documents have a single owner and can be asserted with
# terraform test alone, with known ARNs. The root cannot assert them itself
# because the ARNs it passes are unknown at plan time.
#
# Every document below is byte-identical to the one v0.1.0 built as a root
# local. Keep it that way: a change to any statement is a change to the live
# policy of a backend that protects state, and needs its own review.
#
# Lookups that span variables use try(): a missing key renders null and the
# output preconditions in outputs.tf then reject the input with a message that
# names the mismatch, instead of the raw "Invalid index" error.
#
# Dependency note: each document is a separate local that reads only the
# variables it renders. The root feeds key ARNs back into the replication
# policies while the key policies read the replication role ARNs, so a shared
# local (or one object variable) holding all of them would make the key policy
# depend on the key it protects.

locals {
  # A tier's replication role is added to that tier's principals and to no
  # other tier's, which is what keeps one tier's role out of another's documents.
  principals = {
    for tier in var.tiers : tier => concat(
      tolist(var.state_access_principal_arns),
      contains(keys(var.replication_role_arns), tier) ? [var.replication_role_arns[tier]] : [],
    )
  }

  key_administration_statement = {
    Sid    = "KeyAdministration"
    Effect = "Allow"
    Action = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:Get*",
      "kms:List*",
      "kms:Put*",
      "kms:Revoke*",
      "kms:Update*",
      "kms:Disable*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
    ]
    Resource  = "*"
    Principal = { AWS = tolist(var.key_administrator_arns) }
  }

  key_use_actions = [
    "kms:Decrypt",
    "kms:DescribeKey",
    "kms:Encrypt",
    "kms:GenerateDataKey*",
    "kms:ReEncrypt*",
  ]

  key_policies = {
    for tier in var.tiers : tier => jsonencode({
      Version = "2012-10-17"
      Statement = [
        local.key_administration_statement,
        {
          Sid       = "StateEncryptionUse"
          Action    = local.key_use_actions
          Effect    = "Allow"
          Resource  = "*"
          Principal = { AWS = try(local.principals[tier], null) }
        },
      ]
    })
  }

  replica_key_policies = {
    for tier in keys(var.replication_role_arns) : tier => jsonencode({
      Version = "2012-10-17"
      Statement = [
        local.key_administration_statement,
        {
          Sid       = "StateReplicaEncryptionUse"
          Action    = local.key_use_actions
          Effect    = "Allow"
          Resource  = "*"
          Principal = { AWS = try(local.principals[tier], null) }
        },
      ]
    })
  }

  bucket_policies = {
    for tier, arn in var.bucket_arns : tier => jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "DenyInsecureTransport"
          Effect    = "Deny"
          Action    = "s3:*"
          Resource  = [arn, "${arn}/*"]
          Principal = "*"
          Condition = { Bool = { "aws:SecureTransport" = "false" } }
        },
        {
          Sid       = "DenyPrincipalsOutsideStateRoles"
          Effect    = "Deny"
          Action    = "s3:*"
          Resource  = [arn, "${arn}/*"]
          Principal = "*"
          Condition = { ArnNotEquals = { "aws:PrincipalArn" = try(local.principals[tier], null) } }
        },
        {
          Sid       = "AllowStateBucketMetadata"
          Effect    = "Allow"
          Action    = ["s3:GetBucketLocation", "s3:GetBucketVersioning", "s3:ListBucket"]
          Resource  = arn
          Principal = { AWS = tolist(var.state_access_principal_arns) }
        },
        {
          Sid       = "AllowStateAndLockObjects"
          Effect    = "Allow"
          Action    = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
          Resource  = "${arn}/*"
          Principal = { AWS = tolist(var.state_access_principal_arns) }
        },
      ]
    })
  }

  replica_bucket_policies = {
    for tier, arn in var.replica_bucket_arns : tier => jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "DenyInsecureTransport"
          Effect    = "Deny"
          Action    = "s3:*"
          Resource  = [arn, "${arn}/*"]
          Principal = "*"
          Condition = { Bool = { "aws:SecureTransport" = "false" } }
        },
        {
          Sid       = "DenyPrincipalsOutsideStateRecoveryAndReplicationRoles"
          Effect    = "Deny"
          Action    = "s3:*"
          Resource  = [arn, "${arn}/*"]
          Principal = "*"
          Condition = { ArnNotEquals = { "aws:PrincipalArn" = try(local.principals[tier], null) } }
        },
        {
          Sid       = "AllowStateRecoveryBucketMetadata"
          Effect    = "Allow"
          Action    = ["s3:GetBucketLocation", "s3:GetBucketVersioning", "s3:ListBucket"]
          Resource  = arn
          Principal = { AWS = tolist(var.state_access_principal_arns) }
        },
        {
          Sid       = "AllowReplicatedStateRecoveryObjects"
          Effect    = "Allow"
          Action    = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
          Resource  = "${arn}/*"
          Principal = { AWS = tolist(var.state_access_principal_arns) }
        },
      ]
    })
  }

  replication_policies = {
    for tier in keys(var.replication_role_arns) : tier => jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "ReadSourceBucketReplicationConfiguration"
          Effect   = "Allow"
          Action   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
          Resource = try(var.bucket_arns[tier], null)
        },
        {
          Sid    = "ReadSourceObjectVersionsForReplication"
          Effect = "Allow"
          Action = [
            "s3:GetObjectVersionForReplication",
            "s3:GetObjectVersionAcl",
            "s3:GetObjectVersionTagging",
            "s3:GetObjectRetention",
            "s3:GetObjectLegalHold",
          ]
          Resource = try("${var.bucket_arns[tier]}/*", null)
        },
        {
          Sid    = "WriteReplicatedObjectVersions"
          Effect = "Allow"
          Action = [
            "s3:ReplicateObject",
            "s3:ReplicateDelete",
            "s3:ReplicateTags",
            "s3:ObjectOwnerOverrideToBucketOwner",
          ]
          Resource = try("${var.replica_bucket_arns[tier]}/*", null)
        },
        {
          Sid      = "DecryptPrimaryStateKeys"
          Effect   = "Allow"
          Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
          Resource = try(var.key_arns[tier], null)
        },
        {
          Sid      = "EncryptReplicaStateKeys"
          Effect   = "Allow"
          Action   = ["kms:Encrypt", "kms:GenerateDataKey"]
          Resource = try(var.replica_key_arns[tier], null)
        },
      ]
    })
  }
}
