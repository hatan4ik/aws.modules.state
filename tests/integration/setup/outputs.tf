output "name_prefix" {
  description = "Unique name prefix (the given prefix plus a random suffix) for the module under test."
  value       = local.prefix
}

output "region" {
  description = "Region the suite runs in, from the environment; used as both the primary and the replica Region because the smoke tier does not replicate."
  value       = data.aws_region.current.region
}

output "state_bucket_name" {
  description = "Unique name for the state bucket under test."
  value       = local.state_bucket_name
}

output "access_log_bucket_name" {
  description = "Name of the throwaway central access-log bucket, which allows S3 server access log delivery for the buckets under test."
  value       = aws_s3_bucket.logs.id
}

output "access_log_prefix" {
  description = "Prefix inside the throwaway log bucket for the buckets under test."
  value       = "state-it/terraform-state"
}

output "state_access_principal_arns" {
  description = "The role this suite runs as and the throwaway stand-in for the break-glass role."
  value       = [local.caller_role_arn, aws_iam_role.break_glass.arn]
}

output "key_administrator_arns" {
  description = "The role this suite runs as, which must be able to manage the keys it creates."
  value       = [local.caller_role_arn]
}

output "tags" {
  description = "Identifying tags for the resources under test."
  value       = local.tags
}
