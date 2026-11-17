# terraform-aws-route53-dnssec-zone

A **public Route 53 hosted zone, signed with DNSSEC**, and the KMS key that signs
it. Use it for every public domain: signing comes with the zone, so no domain is
left unsigned by omission.

- **The root module** creates the zone (`prevent_destroy`), one key-signing key
  (KSK) on a KMS key you pass in, and the zone's DNSSEC signing. Route 53 manages
  the zone-signing key itself.
- **`modules/signing-key`** creates that KMS key: an asymmetric `ECC_NIST_P256`
  signing key in **us-east-1**, whose policy lets Route 53's DNSSEC service use
  it for this account's hosted zones only. Call it **once per account**; every
  signed zone there shares the key.

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1" # Route 53 accepts DNSSEC keys from us-east-1 only
}

module "dnssec_signing_key" {
  source    = "github.com/OmronHealthCare-OHI/terraform-aws-route53-dnssec-zone//modules/signing-key?ref=0.1.0"
  providers = { aws = aws.us_east_1 }

  context = module.label.context
}

module "example_com" {
  source = "github.com/OmronHealthCare-OHI/terraform-aws-route53-dnssec-zone?ref=0.1.0"

  name        = "example"
  domain_name = "example.com"
  kms_key_arn = module.dnssec_signing_key.key_arn
  context     = module.label.context
}
```

The `zone` output has the shape of aws-organization's `<name>_domain_zone`
outputs (`arn`, `name`, `zone_id`), so it can be published as is.

## Going live

Signing a zone the internet doesn't ask yet is harmless, so apply first, then
work outward, one step at a time:

1. **Apply.** The zone exists and signs. Nothing resolves through it yet.
2. **Delegate.** Set the domain's name servers at the registrar to the
   `name_servers` output. Wait until the parent zone's old NS records have
   expired (their TTL, often 48 hours).
3. **Add the DS record** at the registrar from the `ds_record` output. Registrar
   forms usually ask for the four fields: key tag, algorithm (13, ECDSA P-256),
   digest type (2, SHA-256) and digest. From then on, validating resolvers
   check every answer.
4. **Watch** Route 53's `DNSSECInternalFailure` and
   `DNSSECKeySigningKeysNeedingAction` metrics for the zone. Either one means
   the domain may stop resolving for validating resolvers.

## What can break a signed domain

Once the registrar has the DS record, these make the domain fail validation,
which looks to users like the domain is gone:

- **The KMS key** disabled, scheduled for deletion, or with Route 53 removed from
  its policy. The key has `prevent_destroy` and a 30-day deletion window, so a
  scheduled deletion can still be cancelled. Deny the pipeline `kms:DisableKey`,
  `kms:ScheduleKeyDeletion` and `kms:PutKeyPolicy` on it.
- **The KSK** deactivated or deleted, which changing `key_signing_key_name` or
  `kms_key_arn` does. Rotate instead (below).
- **Signing turned off** (`signing_status = "NOT_SIGNING"`) while the DS record
  is still at the registrar.
- **The zone** deleted and re-created: new name servers, and no DS match. The zone
  has `prevent_destroy`.

## Turning DNSSEC off

In this order, because a signed parent pointing at an unsigned zone fails the
whole domain:

1. Remove the DS record at the registrar.
2. Wait for its TTL to pass at the parent (often a day or two).
3. Apply with `signing_status = "NOT_SIGNING"`.

## Rotating the key-signing key

Route 53 rotates the zone-signing key itself. The KSK is rotated by hand, and
this module holds one KSK, so a rotation is a short series of changes:

1. Add a second KSK on the same zone (outside this module, or in a later version
   that holds two), and add its DS record at the registrar next to the first.
2. Wait for the DS TTL.
3. Remove the first DS record, wait again, then remove the first KSK.

## Permissions the deploying identity needs

The Route 53 calls these resources make (hashicorp/aws 6.72.0):

| Resource | Calls |
|---|---|
| `aws_route53_zone` | `CreateHostedZone`, `GetChange`, `GetHostedZone`, `ListTagsForResource`, `ChangeTagsForResource`, `UpdateHostedZoneComment` |
| `aws_route53_key_signing_key` | `CreateKeySigningKey`, `ActivateKeySigningKey`, `DeactivateKeySigningKey`, `GetDNSSEC`, `GetChange` |
| `aws_route53_hosted_zone_dnssec` | `EnableHostedZoneDNSSEC`, `DisableHostedZoneDNSSEC`, `GetDNSSEC`, `GetChange` |

Grant `DeleteHostedZone` and `DeleteKeySigningKey` to no pipeline. The
signing-key submodule also needs the usual KMS key-management calls in us-east-1
(create the key, set its policy, tag it, create the alias, and read all of them
back).

## Local development

Install the toolchain (via [mise](https://mise.jdx.dev):
`mise use -g terraform tflint terraform-docs checkov pre-commit`), then:

```sh
pre-commit install
terraform init -backend=false
terraform validate
terraform test
pre-commit run --all-files
```

`tests/zone.tftest.hcl` plans the root module against a mocked provider.
`tests/signing-key.tftest.hcl` plans the submodule against a real provider with
fake credentials, because the key policy is rendered by `aws_iam_policy_document`,
which a mocked provider replaces with random text. The three data sources that
would call AWS are overridden, so no request leaves the machine.

`terraform init` and `terraform test` reach GitHub to fetch the label module and
the Terraform Registry for the `cloudposse/label/null` it wraps, so both need
network access.

See [CONTRIBUTING.md](CONTRIBUTING.md) for versioning and releases.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |

### Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.73.0 |

### Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_label"></a> [label](#module\_label) | github.com/OmronHealthCare-OHI/terraform-null-label | 1.0.0 |

### Resources

| Name | Type |
| ---- | ---- |
| [aws_route53_hosted_zone_dnssec.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_hosted_zone_dnssec) | resource |
| [aws_route53_key_signing_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_key_signing_key) | resource |
| [aws_route53_zone.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_comment"></a> [comment](#input\_comment) | The zone's comment. Defaults to "Public DNS for <domain\_name>, signed with DNSSEC". | `string` | `null` | no |
| <a name="input_context"></a> [context](#input\_context) | Label context from the caller's terraform-null-label instance. Supplies the <namespace>-<region>-<stage> id segments, the ohi:* tag hierarchy and any attributes. | <pre>object({<br/>    enabled              = optional(bool, true)<br/>    namespace            = optional(string, null)<br/>    region               = optional(string, null)<br/>    stage                = optional(string, null)<br/>    aws_region           = optional(string, null)<br/>    application          = optional(string, null)<br/>    module               = optional(string, null)<br/>    stack_suffix         = optional(string, null)<br/>    stack_name_enabled   = optional(bool, true)<br/>    owner                = optional(string, null)<br/>    name                 = optional(string, null)<br/>    attributes           = optional(list(string), [])<br/>    delimiter            = optional(string, "-")<br/>    tag_prefix           = optional(string, "ohi")<br/>    tag_delimiter        = optional(string, ":")<br/>    id_length_limit      = optional(number, null)<br/>    max_tag_key_length   = optional(number, null)<br/>    max_tag_value_length = optional(number, null)<br/>    tags                 = optional(map(string), {})<br/>  })</pre> | n/a | yes |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | The domain the zone serves, e.g. example.com: lowercase, no trailing dot, an internationalized name in its Punycode (xn--) form. Changing it replaces the zone, which prevent\_destroy refuses. | `string` | n/a | yes |
| <a name="input_extra_tags"></a> [extra\_tags](#input\_extra\_tags) | Additional tags merged with the label's generated ohi:* and CloudPosse tags. On a key collision the GENERATED tags win, so Namespace/Environment/Stage/Name and the ohi:* keys cannot be overridden or cleared. Passed through the label module, so its AWS tag constraints apply — including the 50-tag cap, which counts the generated tags. | `map(string)` | `{}` | no |
| <a name="input_key_signing_key_name"></a> [key\_signing\_key\_name](#input\_key\_signing\_key\_name) | Name of the key-signing key, unique within the zone. Changing it replaces the KSK, and with it the DS record the registrar must carry: rotate by the procedure in README.md, not by renaming. | `string` | `"primary"` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the KMS key the key-signing key is backed by: an asymmetric ECC\_NIST\_P256 SIGN\_VERIFY key in us-east-1 whose policy admits Route 53's DNSSEC service. The signing-key submodule creates one; pass its key\_arn. A key ARN, not an alias. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Leaf name for this module's label, e.g. the domain without its top-level domain (connectstudios). Becomes the label's name segment and the Name tag. | `string` | n/a | yes |
| <a name="input_signing_status"></a> [signing\_status](#input\_signing\_status) | SIGNING, or NOT\_SIGNING to turn DNSSEC off. Turn it off only after the DS record is gone from the registrar and its TTL has passed: a signed parent pointing at an unsigned zone fails validation for the whole domain. | `string` | `"SIGNING"` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ds_record"></a> [ds\_record](#output\_ds\_record) | The DS record for the registrar, as the record string (key tag, algorithm, digest type, digest) and as its four fields, which registrar forms ask for separately. Add it only once delegation to name\_servers has propagated. |
| <a name="output_id"></a> [id](#output\_id) | The name the label composed for this module. |
| <a name="output_label_context"></a> [label\_context](#output\_label\_context) | The context this module's label resolved to, for composing child labels that inherit its naming hierarchy. The leaf name is withheld: the label has a single name slot, so a child that inherited it would compose an id identical to this module's. Child labels must set their own name, and it replaces this one rather than nesting under it, so keep child names unique within the namespace/application hierarchy. |
| <a name="output_name_servers"></a> [name\_servers](#output\_name\_servers) | The four name servers Route 53 assigned the zone, for the registrar's NS records. Delegate to these before adding the DS record. |
| <a name="output_signing_status"></a> [signing\_status](#output\_signing\_status) | The zone's DNSSEC signing status: SIGNING or NOT\_SIGNING. |
| <a name="output_tags"></a> [tags](#output\_tags) | The tags applied to the zone: the label's ohi:* set and Name, merged with extra\_tags. |
| <a name="output_zone"></a> [zone](#output\_zone) | The hosted zone as an object: arn, name and zone\_id. The shape of aws-organization's <name>\_domain\_zone outputs, so a caller can publish it as is. |
| <a name="output_zone_id"></a> [zone\_id](#output\_zone\_id) | The hosted zone's id. |
| <a name="output_zone_name"></a> [zone\_name](#output\_zone\_name) | The hosted zone's name: the domain. |
<!-- END_TF_DOCS -->
