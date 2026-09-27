# Advisory checks: they warn on every plan and apply but never block. Each
# describes a configuration that is valid yet usually unintended.

check "key_administrators_are_not_routine_state_users" {
  assert {
    condition     = length(setintersection(var.key_administrator_arns, var.state_access_principal_arns)) == 0
    error_message = "A key administrator is also a state access principal (${join(", ", sort(tolist(setintersection(var.key_administrator_arns, var.state_access_principal_arns))))}). Keep key administration separate from routine state use so a compromised CI role cannot also change or delete the key. The overlap is expected only for the bootstrap identity that applies this module, which must be named in both lists."
  }
}

check "object_lock_settings_are_used" {
  assert {
    condition     = length(local.object_lock_ignored_tiers) == 0
    error_message = "retention_mode or retention_days is set on tier(s) ${join(", ", local.object_lock_ignored_tiers)} while object_lock.enabled is false, so no retention applies. Enable Object Lock at creation or remove the settings."
  }
}

check "object_lock_retention_outlives_noncurrent_expiration" {
  assert {
    condition     = length(local.object_lock_retention_outlives_expiration_tiers) == 0
    error_message = "Object Lock retention is longer than noncurrent_version_expiration_in_days on tier(s) ${join(", ", local.object_lock_retention_outlives_expiration_tiers)}. Lifecycle cannot remove a locked version, so noncurrent versions live for the retention period instead of the configured expiry."
  }
}

check "tags_are_not_overwritten_by_the_module" {
  assert {
    condition     = length(setintersection(toset(keys(var.tags)), toset(local.module_owned_tag_keys))) == 0
    error_message = "tags sets ${join(", ", sort(tolist(setintersection(toset(keys(var.tags)), toset(local.module_owned_tag_keys)))))}, which the module computes itself (${join(", ", local.module_owned_tag_keys)}); the module's value wins. Remove the key from tags."
  }
}
