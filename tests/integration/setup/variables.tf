variable "name_prefix" {
  description = "Prefix of every disposable name; a random suffix is appended so concurrent runs never collide. 1-15 lowercase letters, digits and hyphens, starting with a letter, so the suffixed prefix stays a valid module name_prefix and every derived name stays within its service limits."
  type        = string
  default     = "state-it"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,14}$", var.name_prefix))
    error_message = "name_prefix must be 1-15 lowercase letters, digits or hyphens and start with a letter."
  }
}

variable "tags" {
  description = "Tags applied to the disposable resources in addition to the identifying defaults."
  type        = map(string)
  default     = {}
}
