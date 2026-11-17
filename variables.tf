variable "name" {
  type        = string
  description = "Leaf name for this module's label, e.g. the domain without its top-level domain (connectstudios). Becomes the label's name segment and the Name tag."

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.name))
    error_message = "name may only contain letters, digits, hyphens and underscores."
  }
}

variable "domain_name" {
  type        = string
  description = "The domain the zone serves, e.g. example.com: lowercase, no trailing dot. Changing it replaces the zone, which prevent_destroy refuses."

  validation {
    condition     = length(var.domain_name) <= 253 && can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.domain_name))
    error_message = "domain_name must be a lowercase domain name of two or more labels, with no trailing dot, e.g. example.com."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the KMS key the key-signing key is backed by: an asymmetric ECC_NIST_P256 SIGN_VERIFY key in us-east-1 whose policy admits Route 53's DNSSEC service. The signing-key submodule creates one; pass its key_arn. A key ARN, not an alias."

  validation {
    condition     = can(regex("^arn:aws:kms:us-east-1:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN in us-east-1 (arn:aws:kms:us-east-1:<account>:key/<id>): Route 53 accepts DNSSEC keys from us-east-1 only, and not by alias."
  }
}

variable "key_signing_key_name" {
  type        = string
  description = "Name of the key-signing key, unique within the zone. Changing it replaces the KSK, and with it the DS record the registrar must carry: rotate by the procedure in README.md, not by renaming."
  default     = "primary"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]{3,128}$", var.key_signing_key_name))
    error_message = "key_signing_key_name must be 3 to 128 letters, digits or underscores."
  }
}

variable "signing_status" {
  type        = string
  description = "SIGNING, or NOT_SIGNING to turn DNSSEC off. Turn it off only after the DS record is gone from the registrar and its TTL has passed: a signed parent pointing at an unsigned zone fails validation for the whole domain."
  default     = "SIGNING"

  validation {
    condition     = contains(["SIGNING", "NOT_SIGNING"], var.signing_status)
    error_message = "signing_status must be SIGNING or NOT_SIGNING."
  }
}

variable "comment" {
  type        = string
  description = "The zone's comment. Defaults to \"Public DNS for <domain_name>, signed with DNSSEC\"."
  default     = null
}

# Naming and tags come from the shared label module. Its context object is
# reproduced here verbatim so callers can pass `context = module.label.context`
# and the module inherits namespace/region/stage and the ohi:* hierarchy. Keep
# this block in step with terraform-null-label: it is the contract, not a
# convenience. Terraform drops object attributes the target type does not
# declare rather than erroring, so a field missing here is lost in silence, with
# a green plan and the wrong names.
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
  # No default: the zone is tagged from the label, and a caller without a
  # context has nothing this module can tag it with.
  nullable = false

  # No stage-collision validation: the zone is named by its domain, not by the
  # label id, so two contexts that compose the same id cannot collide here.
}

variable "extra_tags" {
  type        = map(string)
  description = "Additional tags merged with the label's generated ohi:* and CloudPosse tags. On a key collision the GENERATED tags win, so Namespace/Environment/Stage/Name and the ohi:* keys cannot be overridden or cleared. Passed through the label module, so its AWS tag constraints apply — including the 50-tag cap, which counts the generated tags."
  default     = {}
}
