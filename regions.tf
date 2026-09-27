# The Region each provider is actually configured for. ADR 0008's 2026-09-20
# amendment requires the provider aliases to be bound to the declared primary and
# replica Regions; a mis-bound alias would create replicas in the wrong Region
# while the outputs still name the declared one. No input can supply this value,
# so it is read from the providers. Neither data source makes an API call.
#
# The preconditions that compare them live on aws_kms_key.state and
# aws_kms_replica_key.state, the first stateful resource in each Region.

data "aws_region" "primary" {}

data "aws_region" "replica" {
  provider = aws.replica
}
