variable "name" {
  type        = string
  description = "Leaf name for the key's label, e.g. dnssec. Becomes the label's name segment, the alias (alias/<label id>) and the Name tag."
  default     = "dnssec"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.name))
    error_message = "name may only contain letters, digits, hyphens and underscores."
  }
}

variable "deletion_window_in_days" {
  type        = number
  description = "Days between scheduling the key's deletion and deleting it, 7 to 30. The longest by default: a key that signs a live zone must be recoverable."
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30 && floor(var.deletion_window_in_days) == var.deletion_window_in_days
    error_message = "deletion_window_in_days must be a whole number from 7 to 30."
  }
}

# The same context object as the root module's variables.tf: keep the two, and
# terraform-null-label, in step.
variable "context" {
  description = "Label context from the caller's terraform-null-label instance. Supplies the <namespace>-<region>-<stage> id segments, the ohi:* tag hierarchy and any attributes."
  type = object({
    enabled              = optional(bool, true)
    namespace            = optional(string, null)
    region               = optional(string, null)
    stage                = optional(string, null)
    aws_region           = optional(string, null)
    application          = optional(string, null)
    module               = optional(string, null)
    stack_suffix         = optional(string, null)
    stack_name_enabled   = optional(bool, true)
    owner                = optional(string, null)
    name                 = optional(string, null)
    attributes           = optional(list(string), [])
    delimiter            = optional(string, "-")
    tag_prefix           = optional(string, "ohi")
    tag_delimiter        = optional(string, ":")
    id_length_limit      = optional(number, null)
    max_tag_key_length   = optional(number, null)
    max_tag_value_length = optional(number, null)
    tags                 = optional(map(string), {})
  })
  nullable = false
}

variable "extra_tags" {
  type        = map(string)
  description = "Additional tags merged with the label's generated tags. On a key collision the GENERATED tags win."
  default     = {}
}
