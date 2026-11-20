variable "parent_zone" {
  type = object({
    name    = string
    zone_id = string
  })
  description = "The zone to delegate from, as name and zone_id. The root module's zone output and aws-organization's hostedZone objects fit as they are; other attributes are ignored."
  nullable    = false

  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.parent_zone.zone_id))
    error_message = "parent_zone.zone_id must be a Route 53 hosted zone id, e.g. Z0123456789ABCDEFGHIJ."
  }
}

variable "domain_name" {
  type        = string
  description = "The subdomain to delegate, e.g. test.example.com: lowercase, no trailing dot, below parent_zone's name. The subdomain zone's zone_name output."
  nullable    = false

  validation {
    # The root module's domain_name pattern.
    condition     = length(var.domain_name) <= 253 && can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+([a-z]{2,63}|xn--[a-z0-9]([a-z0-9-]{0,57}[a-z0-9])?)$", var.domain_name))
    error_message = "domain_name must be a lowercase domain name with no trailing dot, e.g. test.example.com; an internationalized name in its Punycode form."
  }

  validation {
    # A name outside the parent zone would be refused by Route 53 at apply. The
    # leading dot keeps notexample.com out of example.com, and the parent
    # itself out too: its NS record is Route 53's own.
    condition     = endswith(var.domain_name, ".${trimsuffix(lower(var.parent_zone.name), ".")}")
    error_message = "domain_name must be a subdomain of parent_zone.name, e.g. test.example.com under example.com."
  }
}

variable "name_servers" {
  type        = list(string)
  description = "The subdomain zone's name servers, from its name_servers output."
  nullable    = false

  validation {
    # An empty NS record is refused at apply.
    condition     = length(var.name_servers) > 0
    error_message = "name_servers must list the subdomain zone's name servers."
  }

  validation {
    condition     = alltrue([for ns in var.name_servers : can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9-]{2,63}$", ns))])
    error_message = "Each name server must be a lowercase host name with no trailing dot, e.g. ns-123.awsdns-45.com."
  }
}

variable "ds_records" {
  type        = map(string)
  description = "The DS records the parent publishes for the subdomain, keyed by the subdomain's key-signing key name: ds_records[<name>].record from the subdomain zone. One, two during a rotation, or none for a delegation without a chain of trust. Publish a record only once the subdomain zone signs, and change this map only in the order README.md gives: removing a record the subdomain's KSK still needs, or one whose TTL has not passed, makes the subdomain fail validation."
  default     = {}
  nullable    = false

  validation {
    # A zone holds at most two KSKs, so the parent never needs more.
    condition     = length(var.ds_records) <= 2
    error_message = "ds_records may hold at most two records: a zone has at most two key-signing keys."
  }

  validation {
    # Key tag, algorithm, digest type, digest: Route 53's ds_record format.
    condition     = alltrue([for ds in values(var.ds_records) : can(regex("^[0-9]{1,5} [0-9]{1,3} [0-9]{1,3} [0-9A-Fa-f]+$", ds))])
    error_message = "Each ds_records value must be a DS record: key tag, algorithm, digest type and digest, separated by single spaces, e.g. \"12345 13 2 ABCDEF...\"."
  }

  validation {
    # The record set would fold two equal records into one, so a copy-pasted
    # record would leave one key-signing key without its DS record in silence.
    # Compared in one case, because the digest is hex and the format check
    # above accepts either case.
    condition     = length(distinct([for ds in values(var.ds_records) : upper(ds)])) == length(var.ds_records)
    error_message = "ds_records must hold a different record for each key-signing key."
  }
}

variable "ns_ttl" {
  type        = number
  description = "TTL of the NS record, in seconds. Two days by default, as Route 53 sets on a zone's own NS record."
  default     = 172800
  nullable    = false

  validation {
    condition     = var.ns_ttl >= 60 && floor(var.ns_ttl) == var.ns_ttl
    error_message = "ns_ttl must be a whole number of seconds, at least 60."
  }
}

variable "ds_ttl" {
  type        = number
  description = "TTL of the DS record, in seconds. An hour by default: every step of a key-signing-key rotation waits for it, so a TLD's day-long DS TTL would make each wait a day."
  default     = 3600
  nullable    = false

  validation {
    condition     = var.ds_ttl >= 60 && floor(var.ds_ttl) == var.ds_ttl
    error_message = "ds_ttl must be a whole number of seconds, at least 60."
  }
}
