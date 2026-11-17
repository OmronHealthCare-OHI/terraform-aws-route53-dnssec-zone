# signing-key

The KMS key one Route 53 key-signing key (KSK) signs with: an asymmetric
`ECC_NIST_P256` `SIGN_VERIFY` key in **us-east-1**, with a 30-day deletion
window. Its policy lets the account's own IAM administer it, as in KMS's default
key policy, and lets Route 53's DNSSEC service (`dnssec-route53.amazonaws.com`)
describe it, read its public key, sign, and create grants for AWS resources, for
this account and the one hosted zone it is for only (`aws:SourceAccount`, and
`aws:SourceArn` equal to that zone's ARN).

The root module calls it once per entry in `key_signing_keys`, because Route 53
requires each of a zone's KSKs to use a different KMS key, including the second
one a rotation adds. There is no need to call it yourself. Give it a provider
configured for us-east-1; it refuses any other region.

The key has **no `prevent_destroy`**, so that a rotation can retire it with a
reviewed apply. See the [root README](../../README.md) for why that is safe, for
rotation, and for what breaks a signed domain.

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

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_label"></a> [label](#module\_label) | github.com/OmronHealthCare-OHI/terraform-null-label | 1.0.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_context"></a> [context](#input\_context) | Label context from the caller's terraform-null-label instance. Supplies the <namespace>-<region>-<stage> id segments, the ohi:* tag hierarchy and any attributes. | <pre>object({<br/>    enabled              = optional(bool, true)<br/>    namespace            = optional(string, null)<br/>    region               = optional(string, null)<br/>    stage                = optional(string, null)<br/>    aws_region           = optional(string, null)<br/>    application          = optional(string, null)<br/>    module               = optional(string, null)<br/>    stack_suffix         = optional(string, null)<br/>    stack_name_enabled   = optional(bool, true)<br/>    owner                = optional(string, null)<br/>    name                 = optional(string, null)<br/>    attributes           = optional(list(string), [])<br/>    delimiter            = optional(string, "-")<br/>    tag_prefix           = optional(string, "ohi")<br/>    tag_delimiter        = optional(string, ":")<br/>    id_length_limit      = optional(number, null)<br/>    max_tag_key_length   = optional(number, null)<br/>    max_tag_value_length = optional(number, null)<br/>    tags                 = optional(map(string), {})<br/>  })</pre> | n/a | yes |
| <a name="input_deletion_window_in_days"></a> [deletion\_window\_in\_days](#input\_deletion\_window\_in\_days) | Days between scheduling the key's deletion and deleting it, 7 to 30. The longest by default: a key that signs a live zone must be recoverable. | `number` | `30` | no |
| <a name="input_extra_tags"></a> [extra\_tags](#input\_extra\_tags) | Additional tags merged with the label's generated tags. On a key collision the GENERATED tags win. | `map(string)` | `{}` | no |
| <a name="input_hosted_zone_id"></a> [hosted\_zone\_id](#input\_hosted\_zone\_id) | Id of the one hosted zone whose key-signing key this key backs. The key policy lets Route 53 use the key for that zone only. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Leaf name for the key's label, e.g. dnssec. Becomes the label's name segment, the alias (alias/<label id>) and the Name tag. | `string` | `"dnssec"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alias_name"></a> [alias\_name](#output\_alias\_name) | The key's alias, alias/<label id>. |
| <a name="output_key_arn"></a> [key\_arn](#output\_key\_arn) | The KMS key's ARN, for the key-signing key it backs. |
| <a name="output_key_id"></a> [key\_id](#output\_key\_id) | The KMS key's id. |
<!-- END_TF_DOCS -->
