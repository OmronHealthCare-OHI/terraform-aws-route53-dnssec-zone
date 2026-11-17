output "key_arn" {
  description = "The KMS key's ARN: pass it to the root module's kms_key_arn."
  value       = aws_kms_key.this.arn
}

output "key_id" {
  description = "The KMS key's id."
  value       = aws_kms_key.this.key_id
}

output "alias_name" {
  description = "The key's alias, alias/<label id>."
  value       = aws_kms_alias.this.name
}
