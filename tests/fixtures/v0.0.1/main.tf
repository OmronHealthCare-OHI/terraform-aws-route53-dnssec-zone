# A snapshot of the root module as released in 0.0.1, for tests/upgrade.tftest.hcl:
# its first run applies this, and the next plans the current module on the same
# state, so the moved blocks in main.tf are tested against the addresses 0.0.1
# actually wrote. Do not edit it to follow the module; it is history.
#
# One line differs from the release: the signing-key source, so it resolves from
# here. That points at the current submodule, whose addresses (aws_kms_key.this,
# aws_kms_alias.this) are the same as 0.0.1's; only its lifecycle changed.

# A public Route 53 hosted zone, signed with DNSSEC.
#
# Four resources, always together: the zone, its own KMS signing key (the
# signing-key submodule), one key-signing key (KSK) backed by that key, and the
# zone's DNSSEC signing. Route 53 manages the zone-signing key itself.
#
# One KMS key per zone, not one shared by every zone in the account: a key
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
# so the domain stops resolving until the registrar is updated; with DNSSEC on,
# a lost KSK or KMS key does the same to every validating resolver until the DS
# record at the registrar is replaced. Neither belongs to a routine apply.
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
  source = "../../../modules/signing-key"

  name           = "${var.name}-dnssec"
  hosted_zone_id = aws_route53_zone.this.zone_id
  context        = var.context
  extra_tags     = var.extra_tags
}

resource "aws_route53_key_signing_key" "this" {
  hosted_zone_id             = aws_route53_zone.this.zone_id
  key_management_service_arn = module.signing_key.key_arn
  name                       = var.key_signing_key_name

  # Only an ACTIVE KSK signs. Deactivating it is a step in rotation or in
  # turning DNSSEC off, never on its own while the registrar has its DS record.
  status = "ACTIVE"
}

resource "aws_route53_hosted_zone_dnssec" "this" {
  # Through the KSK, so signing starts only once the KSK exists, and stops
  # before it is removed.
  hosted_zone_id = aws_route53_key_signing_key.this.hosted_zone_id
  signing_status = var.signing_status
}
