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

output "ds_record" {
  description = "The DS record for the registrar, as the record string (key tag, algorithm, digest type, digest) and as its four fields, which registrar forms ask for separately. Add it only once delegation to name_servers has propagated."
  value = {
    record      = aws_route53_key_signing_key.this.ds_record
    key_tag     = aws_route53_key_signing_key.this.key_tag
    algorithm   = aws_route53_key_signing_key.this.signing_algorithm_type
    digest_type = aws_route53_key_signing_key.this.digest_algorithm_type
    digest      = aws_route53_key_signing_key.this.digest_value
  }

  # The KSK exists before the zone signs. A DS record built from this output in
  # a parent zone Terraform manages must not be created until signing is on:
  # a DS record for a zone that doesn't sign fails validation for the whole
  # domain.
  depends_on = [aws_route53_hosted_zone_dnssec.this]
}

output "kms_key_arn" {
  description = "ARN of this zone's KMS signing key, in us-east-1: for alarms, audits, and the key policy reviews a broken key would call for."
  value       = module.signing_key.key_arn
}

output "kms_key_alias" {
  description = "Alias of this zone's KMS signing key, alias/<label id>-dnssec."
  value       = module.signing_key.alias_name
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
