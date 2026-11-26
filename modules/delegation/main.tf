# Delegation of a subdomain from its parent zone: the NS record that hands the
# subdomain to its own zone, and the DS record that carries the chain of trust
# down to it. Both live in the PARENT zone, so this module runs with the
# parent's provider, which is often another account than the subdomain's zone.
#
# That is why delegation is a module of its own rather than a `parent` input on
# the root module: a root module that wrote into the parent would need a second
# provider, and Terraform cannot make a provider optional, so every caller,
# top-level domains included, would have to pass one.
#
# The DS records are named by the caller, not derived from the subdomain's
# key-signing keys. The parent plays the registrar's part in the double-DS
# rotation (README.md), whose steps are separate applies with waits between
# them; publishing whatever KSKs exist, or whichever are ACTIVE, would merge
# "remove the old DS record" and "deactivate the old KSK" into one apply.
#
# No tags: Route 53 records carry none.

locals {
  # A DS record as Route 53 writes it: key tag, algorithm, digest type and
  # digest, numbers without leading zeros, the digest in uppercase hex. The
  # ds_records validations share it.
  ds_record_format = "^(0|[1-9][0-9]{0,4}) (0|[1-9][0-9]{0,2}) (0|[1-9][0-9]{0,2}) [0-9A-F]+$"
}

resource "aws_route53_record" "ns" {
  zone_id = var.parent_zone.zone_id
  name    = var.domain_name
  type    = "NS"
  ttl     = var.ns_ttl
  records = var.name_servers
}

resource "aws_route53_record" "ds" {
  # No DS record at all when none is published: delegation without a chain of
  # trust, which resolves, unvalidated.
  count = length(var.ds_records) > 0 ? 1 : 0

  zone_id = var.parent_zone.zone_id
  name    = var.domain_name
  type    = "DS"
  ttl     = var.ds_ttl

  # One record set, holding both records during a rotation.
  records = values(var.ds_records)

  # A DS record belongs at a delegation point: create it after the NS record,
  # and remove it before.
  depends_on = [aws_route53_record.ns]
}
