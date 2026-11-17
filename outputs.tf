output "zone" {
  description = "The hosted zone as an object: arn, name and zone_id. The shape of aws-organization's hostedZone, so a caller can put it straight into its domain_zones map."
  value = {
    arn     = aws_route53_zone.this.arn
    name    = aws_route53_zone.this.name
    zone_id = aws_route53_zone.this.zone_id
  }
}

output "zone_id" {
  description = "The hosted zone's id."
  value       = aws_route53_zone.this.zone_id
}

output "zone_name" {
  description = "The hosted zone's name: the domain."
  value       = aws_route53_zone.this.name
}

output "name_servers" {
  description = "The four name servers Route 53 assigned the zone, for the registrar's NS records. Delegate to these before adding the DS record."
  value       = aws_route53_zone.this.name_servers
}

output "ds_records" {
  description = "The DS record for the registrar, per key-signing key (keyed as key_signing_keys), as the record string (key tag, algorithm, digest type, digest) and as its four fields, which registrar forms ask for separately, with the KSK's status. Add a record only once delegation to name_servers has propagated, and during a rotation only in the order README.md gives."
  value = {
    for name, ksk in aws_route53_key_signing_key.this : name => {
      record      = ksk.ds_record
      key_tag     = ksk.key_tag
      algorithm   = ksk.signing_algorithm_type
      digest_type = ksk.digest_algorithm_type
      digest      = ksk.digest_value
      status      = ksk.status
    }
  }

  # The KSKs exist before the zone signs. A DS record built from this output in
  # a parent zone Terraform manages must not be created until signing is on:
  # a DS record for a zone that doesn't sign fails validation for the whole
  # domain.
  depends_on = [aws_route53_hosted_zone_dnssec.this]
}

output "kms_key_arns" {
  description = "ARN of each key-signing key's KMS key (keyed as key_signing_keys), in us-east-1: for alarms, audits, and the key policy reviews a broken key would call for."
  value       = { for name, key in module.signing_key : name => key.key_arn }
}

output "kms_key_aliases" {
  description = "Alias of each key-signing key's KMS key (keyed as key_signing_keys): alias/<label id>-dnssec for the entry named primary, alias/<label id>-dnssec-<name> for any other."
  value       = { for name, key in module.signing_key : name => key.alias_name }
}

output "signing_status" {
  description = "The zone's DNSSEC signing status: SIGNING or NOT_SIGNING."
  value       = aws_route53_hosted_zone_dnssec.this.signing_status
}

output "id" {
  description = "The name the label composed for this module."
  value       = local.id
}

output "tags" {
  description = "The tags applied to the zone: the label's ohi:* set and Name, merged with extra_tags."
  value       = local.tags
}

output "label_context" {
  description = "The context this module's label resolved to, for composing child labels that inherit its naming hierarchy. The leaf name is withheld: the label has a single name slot, so a child that inherited it would compose an id identical to this module's. Child labels must set their own name, and it replaces this one rather than nesting under it, so keep child names unique within the namespace/application hierarchy."
  value       = merge(module.label.context, { name = null })
}
