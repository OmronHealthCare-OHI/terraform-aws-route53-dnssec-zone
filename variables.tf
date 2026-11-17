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
  description = "The domain the zone serves, e.g. example.com: lowercase, no trailing dot, an internationalized name in its Punycode (xn--) form. Changing it replaces the zone, which prevent_destroy refuses."

  validation {
    # The top-level label: letters, or an internationalized TLD in its ASCII
    # (Punycode) form, e.g. xn--p1ai.
    condition     = length(var.domain_name) <= 253 && can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+([a-z]{2,63}|xn--[a-z0-9]([a-z0-9-]{0,57}[a-z0-9])?)$", var.domain_name))
    error_message = "domain_name must be a lowercase domain name of two or more labels, with no trailing dot, e.g. example.com; an internationalized name in its Punycode form, e.g. xn--e1afmkfd.xn--p1ai."
  }
}

variable "key_signing_keys" {
  type = map(object({
    status = optional(string, "ACTIVE")
  }))
  description = "The zone's key-signing keys (KSKs), keyed by KSK name: one, or two during a rotation. Each gets a KMS key of its own. status is ACTIVE (the default) or INACTIVE. Renaming or removing an entry deletes its KSK and schedules its key's deletion: do it only as the last step of a rotation (README.md). Route 53 refuses it while the registrar carries that KSK's DS record. A 0.0.1 KSK becomes the entry named primary."
  default     = { primary = {} }
  nullable    = false

  validation {
    # Route 53 allows two KSKs per zone. None would leave nothing to sign with.
    condition     = length(var.key_signing_keys) >= 1 && length(var.key_signing_keys) <= 2
    error_message = "key_signing_keys must have one or two entries: Route 53 allows at most two KSKs per zone, and a second exists only during a rotation."
  }

  validation {
    condition     = alltrue([for name in keys(var.key_signing_keys) : can(regex("^[a-zA-Z0-9_]{3,128}$", name))])
    error_message = "Each key_signing_keys name must be 3 to 128 letters, digits or underscores."
  }

  validation {
    # The name also goes into the key's alias, through the label, which drops
    # underscores and lowercases. Two names that read the same there would ask
    # for one alias twice.
    condition     = length(distinct([for name in keys(var.key_signing_keys) : lower(replace(name, "_", ""))])) == length(var.key_signing_keys)
    error_message = "key_signing_keys names must still differ when lowercased and without underscores: each one names its key's alias."
  }

  validation {
    condition     = alltrue([for ksk in values(var.key_signing_keys) : contains(["ACTIVE", "INACTIVE"], ksk.status)])
    error_message = "Each key_signing_keys status must be ACTIVE or INACTIVE."
  }

  validation {
    # Route 53 refuses to deactivate the only KSK of a zone that signs; say so at
    # plan, not halfway through an apply.
    condition     = var.signing_status != "SIGNING" || anytrue([for ksk in values(var.key_signing_keys) : ksk.status == "ACTIVE"])
    error_message = "A zone that signs needs an ACTIVE key-signing key: keep one entry ACTIVE, or set signing_status to NOT_SIGNING first."
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
