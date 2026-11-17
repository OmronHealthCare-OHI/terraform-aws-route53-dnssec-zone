# A public Route 53 hosted zone, signed with DNSSEC.
#
# The zone, one or two key-signing keys (KSKs), a KMS signing key of its own for
# each KSK (the signing-key submodule), and the zone's DNSSEC signing. Route 53
# manages the zone-signing key itself. One KSK is the steady state; a second
# exists only during a rotation, which follows AWS's double-DS method
# (README.md). Route 53 allows two KSKs per zone, each on a different KMS key.
#
# One KMS key per KSK, never one shared by every zone in the account: a key
# that breaks (a bad key policy, disabled, scheduled for deletion) or is misused
# (kms:Sign forges DNSKEY signatures) then reaches one domain, not all of them,
# and each zone rotates and retires its key on its own. A key costs about a
# dollar a month.
#
# Route 53 accepts DNSSEC signing keys from us-east-1 only, so this module's
# provider must be configured for us-east-1. Route 53 itself is global, so the
# zone does not care; the submodule refuses any other region.
#
# The zone has prevent_destroy. A re-created public zone gets new name servers,
# so the domain stops resolving until the registrar is updated. The KMS keys do
# not, so that a rotation can retire one: Route 53 itself refuses to deactivate
# a KSK whose DS record is still at the parent, or the zone's only KSK while it
# signs, and the provider deactivates a KSK before deleting it, before its key
# (README.md, "Retiring a key").
#
# Signing a zone the internet doesn't ask yet is harmless: until the registrar
# delegates to this zone's name servers and carries its DS record, nothing
# validates it. The order to go live, and to turn signing off, is in README.md.

module "label" {
  source = "github.com/OmronHealthCare-OHI/terraform-null-label?ref=1.0.0"

  context = var.context
  name    = var.name
  tags    = var.extra_tags
}

locals {
  # {namespace}-{region}-{stage}-{application}-{name}-{attributes}. The zone's
  # own name is the domain; the label names nothing here but supplies the tags.
  id   = module.label.id
  tags = module.label.tags
}

resource "aws_route53_zone" "this" {
  #checkov:skip=CKV2_AWS_39: Query logging needs a CloudWatch log group in us-east-1 with a resource policy for Route 53; not required yet, and a caller can add aws_route53_query_log on zone_id.
  name    = var.domain_name
  comment = coalesce(var.comment, "Public DNS for ${var.domain_name}, signed with DNSSEC")

  # No vpc block: a public zone. A private zone can't be signed.
  tags = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

module "signing_key" {
  source   = "./modules/signing-key"
  for_each = var.key_signing_keys

  # The entry named primary keeps the alias 0.0.1 gave the zone's one key,
  # alias/<label id>-dnssec, so upgrading renames nothing. Any other entry adds
  # its name: alias/<label id>-dnssec-<name>.
  name           = each.key == "primary" ? "${var.name}-dnssec" : "${var.name}-dnssec-${each.key}"
  hosted_zone_id = aws_route53_zone.this.zone_id
  context        = var.context
  extra_tags     = var.extra_tags
}

resource "aws_route53_key_signing_key" "this" {
  for_each = var.key_signing_keys

  hosted_zone_id             = aws_route53_zone.this.zone_id
  key_management_service_arn = module.signing_key[each.key].key_arn
  name                       = each.key

  # Only an ACTIVE KSK signs. INACTIVE is a step in retiring a KSK or in
  # turning DNSSEC off, never on its own while the registrar has its DS
  # record; Route 53 refuses it then.
  status = each.value.status
}

resource "aws_route53_hosted_zone_dnssec" "this" {
  hosted_zone_id = aws_route53_zone.this.zone_id
  signing_status = var.signing_status

  # Signing starts only once the KSKs exist, and stops before they are removed.
  depends_on = [aws_route53_key_signing_key.this]
}

# 0.0.1 managed one KSK and one key, without keys. Both become the entry named
# primary, the default, so an upgrade plans no replacement
# (tests/upgrade.tftest.hcl). A caller that set key_signing_key_name to
# something else moves on from primary in its own configuration (README.md,
# "Upgrading from 0.0.1").
moved {
  from = aws_route53_key_signing_key.this
  to   = aws_route53_key_signing_key.this["primary"]
}

moved {
  from = module.signing_key
  to   = module.signing_key["primary"]
}
