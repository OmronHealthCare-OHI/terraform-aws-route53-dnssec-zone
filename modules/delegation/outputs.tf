output "fqdn" {
  description = "The delegated name, as Route 53 holds the NS record."
  value       = aws_route53_record.ns.fqdn
}

output "name_servers" {
  description = "The name servers the parent delegates to."
  value       = aws_route53_record.ns.records
}

output "ds_records" {
  description = "The DS records the parent publishes, keyed as ds_records. Empty when the delegation has no chain of trust."
  value       = var.ds_records

  depends_on = [aws_route53_record.ds]
}
