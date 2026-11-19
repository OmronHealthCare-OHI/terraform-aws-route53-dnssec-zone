# delegation

Delegates a subdomain, such as `test.example.com`, from its parent zone to a zone
of its own: the **NS record** that hands the name to the subdomain's zone, and
the **DS record** that carries the DNSSEC chain of trust down to it. Both records
live in the **parent** zone, so give this module the parent's provider. The
subdomain's zone comes from the root module like any other domain's, often in
another account.

```hcl
module "test_example_com" {
  source    = "github.com/OmronHealthCare-OHI/terraform-aws-route53-dnssec-zone?ref=1.1.0"
  providers = { aws = aws.test_us_east_1 } # the subdomain's account, us-east-1

  name        = "example-test"
  domain_name = "test.example.com"
  context     = module.label.context
}

module "test_example_com_delegation" {
  source    = "github.com/OmronHealthCare-OHI/terraform-aws-route53-dnssec-zone//modules/delegation?ref=1.1.0"
  providers = { aws = aws.parent } # the parent zone's account; any region

  parent_zone  = module.example_com.zone
  domain_name  = module.test_example_com.zone_name
  name_servers = module.test_example_com.name_servers
  ds_records = {
    primary = module.test_example_com.ds_records["primary"].record
  }
}
```

The DS records are **named, not derived**: the parent here does the registrar's
part of a key-signing-key rotation, and each of its steps is an apply of its own
(see the [root README](../../README.md), "Delegating a subdomain"). Leave
`ds_records` empty for a delegation without a chain of trust.

When the subdomain's zone is in the same configuration, the root module's
`ds_records` output waits for signing, so the DS record is never published for a
zone that doesn't sign yet. When it is in another configuration, apply that one
first and carry the values over.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.73.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_route53_record.ds](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.ns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | The subdomain to delegate, e.g. test.example.com: lowercase, no trailing dot, below parent\_zone's name. The subdomain zone's zone\_name output. | `string` | n/a | yes |
| <a name="input_ds_records"></a> [ds\_records](#input\_ds\_records) | The DS records the parent publishes for the subdomain, keyed by the subdomain's key-signing key name: ds\_records[<name>].record from the subdomain zone. One, two during a rotation, or none for a delegation without a chain of trust. Publish a record only once the subdomain zone signs, and change this map only in the order README.md gives: removing a record the subdomain's KSK still needs, or one whose TTL has not passed, makes the subdomain fail validation. | `map(string)` | `{}` | no |
| <a name="input_ds_ttl"></a> [ds\_ttl](#input\_ds\_ttl) | TTL of the DS record, in seconds. An hour by default: every step of a key-signing-key rotation waits for it, so a TLD's day-long DS TTL would make each wait a day. | `number` | `3600` | no |
| <a name="input_name_servers"></a> [name\_servers](#input\_name\_servers) | The subdomain zone's name servers, from its name\_servers output. | `list(string)` | n/a | yes |
| <a name="input_ns_ttl"></a> [ns\_ttl](#input\_ns\_ttl) | TTL of the NS record, in seconds. Two days by default, as Route 53 sets on a zone's own NS record. | `number` | `172800` | no |
| <a name="input_parent_zone"></a> [parent\_zone](#input\_parent\_zone) | The zone to delegate from, as name and zone\_id. The root module's zone output and aws-organization's hostedZone objects fit as they are; other attributes are ignored. | <pre>object({<br/>    name    = string<br/>    zone_id = string<br/>  })</pre> | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ds_records"></a> [ds\_records](#output\_ds\_records) | The DS records the parent publishes, keyed as ds\_records. Empty when the delegation has no chain of trust. |
| <a name="output_fqdn"></a> [fqdn](#output\_fqdn) | The delegated name, as Route 53 holds the NS record. |
| <a name="output_name_servers"></a> [name\_servers](#output\_name\_servers) | The name servers the parent delegates to. |
<!-- END_TF_DOCS -->
