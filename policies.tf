# Every policy document is rendered by modules/policies, a pure renderer with no
# resources, so the security-critical JSON can be asserted with known ARNs. The
# ARNs are passed as five separate maps on purpose: the key policies read the
# replication role ARNs while the replication policies read the key ARNs, and one
# combined object would make a key's policy depend on the key itself.

module "policies" {
  source = "./modules/policies"

  tiers                       = toset(keys(var.state_tiers))
  state_access_principal_arns = var.state_access_principal_arns
  key_administrator_arns      = var.key_administrator_arns

  bucket_arns           = { for tier, bucket in aws_s3_bucket.state : tier => bucket.arn }
  key_arns              = { for tier, key in aws_kms_key.state : tier => key.arn }
  replication_role_arns = { for tier, role in aws_iam_role.state_replication : tier => role.arn }
  replica_bucket_arns   = { for tier, bucket in aws_s3_bucket.state_replica : tier => bucket.arn }
  replica_key_arns      = { for tier, key in aws_kms_replica_key.state : tier => key.arn }
}
