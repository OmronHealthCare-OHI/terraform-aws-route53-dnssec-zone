# A public Route 53 hosted zone, signed with DNSSEC.
#
# Three resources, always together: the zone, one key-signing key (KSK) backed
# by a KMS key the caller passes in, and the zone's DNSSEC signing. Route 53
# manages the zone-signing key itself. The KMS key is not created here: one key
# signs every zone in an account, so it is the signing-key submodule's
# (modules/signing-key), called once per account.
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
  name    = var.domain_name
  comment = coalesce(var.comment, "Public DNS for ${var.domain_name}, signed with DNSSEC")

  # No vpc block: a public zone. A private zone can't be signed.
  tags = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_key_signing_key" "this" {
  hosted_zone_id             = aws_route53_zone.this.zone_id
  key_management_service_arn = var.kms_key_arn
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
