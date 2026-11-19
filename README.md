# terraform-aws-route53-dnssec-zone

A **public Route 53 hosted zone, signed with DNSSEC**, and the KMS key that signs
it. Use it for every public domain: signing comes with the zone, so no domain is
left unsigned by omission.

- **The root module** creates the zone (`prevent_destroy`), its key-signing
  keys (KSKs) from `key_signing_keys`, **a KMS signing key of its own for each
  KSK**, and the zone's DNSSEC signing. One KSK, `primary`, is the default and
  the steady state; a second exists only during a rotation (below). Route 53
  manages the zone-signing key itself.
- **`modules/signing-key`** is one such KMS key: an asymmetric `ECC_NIST_P256`
  signing key in **us-east-1**, whose policy lets Route 53's DNSSEC service use
  it for **this one zone** only. The root module calls it once per KSK.
- **`modules/delegation`** delegates a subdomain with a zone of its own (say
  `test.example.com`) from its parent zone: the NS and DS records in the
  parent. Call it yourself, with the parent's provider ("Delegating a
  subdomain", below).

Route 53 accepts DNSSEC signing keys from us-east-1 only, so give the module a
us-east-1 provider. Route 53 itself is global, so the zone doesn't mind.

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "example_com" {
  source    = "github.com/OmronHealthCare-OHI/terraform-aws-route53-dnssec-zone?ref=1.0.0"
  providers = { aws = aws.us_east_1 }

  name        = "example"
  domain_name = "example.com"
  context     = module.label.context
}
```

The `zone` output has the shape of aws-organization's `hostedZone` (`arn`,
`name`, `zone_id`), so it can go straight into its `domain_zones` map.

### One KMS key per KSK, not one per account

AWS allows a key per account. The module creates one per KSK, because a key
that breaks (a bad key policy, disabled, scheduled for deletion) or is misused
(anyone with `kms:Sign` on it can sign a zone's DNSKEY set) then reaches **one**
domain, not every signed domain in the account. Each key's policy names its own
zone, and each zone rotates and retires its keys on its own. Route 53 requires
a zone's two KSKs to use different keys anyway. A key costs about a dollar a
month.

## Going live

Signing a zone the internet doesn't ask yet is harmless, so apply first, then
work outward, one step at a time. For a subdomain whose parent zone Route 53
holds, the parent takes the registrar's place: see "Delegating a subdomain".

1. **Apply.** The zone exists and signs. Nothing resolves through it yet.
2. **Delegate.** Set the domain's name servers at the registrar to the
   `name_servers` output. Wait until the parent zone's old NS records have
   expired (their TTL, often 48 hours).
3. **Add the DS record** at the registrar from `ds_records["primary"]`. Registrar
   forms usually ask for the four fields: key tag, algorithm (13, ECDSA P-256),
   digest type (2, SHA-256) and digest. From then on, validating resolvers
   check every answer.
4. **Watch** Route 53's `DNSSECInternalFailure` and
   `DNSSECKeySigningKeysNeedingAction` metrics for the zone. Either one means
   the domain may stop resolving for validating resolvers.

## What can break a signed domain

Once the registrar has the DS record, these make the domain fail validation,
which looks to users like the domain is gone:

- **A KMS key that signs** disabled, scheduled for deletion, or with Route 53
  removed from its policy. Keys have a 30-day deletion window, so a scheduled
  deletion can still be cancelled. Deny the pipeline `kms:DisableKey` and
  `kms:PutKeyPolicy` on them, and see "Retiring a key" for
  `kms:ScheduleKeyDeletion`.
- **A KSK whose DS record the registrar carries** deactivated or deleted, which
  renaming or removing its entry in `key_signing_keys` asks for. Route 53
  refuses that (below), so the apply fails instead of the domain; rotate by the
  procedure below.
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

Route 53 rotates the zone-signing key itself, so this concerns the KSK only, and
only on a trigger: a suspected misuse of `kms:Sign` on the key, a change of
algorithm, or a move to another key or account. There is no schedule.

The module follows AWS's double-DS method. A zone holds at most two KSKs, and
Route 53 requires each to use a **different KMS key**, so each entry in
`key_signing_keys` gets one. The names are yours; `primary` and `secondary`
below are examples, and after a rotation the remaining entry keeps its name.
Each step is a reviewed apply or a registrar change, in this order:

1. **Add the new KSK.** Apply with a second entry:

   ```hcl
   key_signing_keys = {
     primary   = {}
     secondary = {}
   }
   ```

   The zone now signs its DNSKEY set with both KSKs. Add the new DS record,
   `ds_records["secondary"]`, at the registrar **next to** the old one. The old
   DS record stays.
2. **Wait for both caches to expire.** Read the TTL of the zone's DNSKEY records
   (`dig <domain> DNSKEY @<one of name_servers>`) and of the DS record at the
   parent (`dig <domain> DS @<one of the parent's name servers>`), and wait at
   least the larger of the two, often two days. Until then some resolvers still
   hold the DNSKEY set from before the new key existed, and only the old DS
   record matches it.
3. **Remove the old DS record** at the registrar, then wait for the DS TTL again:
   resolvers that cached only the old DS record still need the old KSK.
4. **Set the old KSK INACTIVE**, in an apply of its own:

   ```hcl
   key_signing_keys = {
     primary   = { status = "INACTIVE" }
     secondary = {}
   }
   ```

   The zone now signs with the new KSK alone. Check that the domain still
   validates (`dig +dnssec <domain>` through a validating resolver, and the
   `DNSSECKeySigningKeysNeedingAction` metric). INACTIVE can still be undone by
   setting it ACTIVE again; the next step cannot.
5. **Retire the old entry.** Remove it, check that the plan destroys that
   entry's KSK, key and alias and nothing else, and apply. Terraform deletes the
   KSK (Route 53 deletes only an INACTIVE KSK) and then schedules its KMS key's
   deletion, 30 days out.

Watch `DNSSECInternalFailure` and `DNSSECKeySigningKeysNeedingAction`
throughout.

### Retiring a key

The KMS keys have **no `prevent_destroy`**, so step 5 is a plain apply. That
was a choice between three ways to let one key go while the other stays:

| | Retires one key in a reviewed apply | Guard against deleting a key that signs |
|---|---|---|
| **A `removed` block** (`lifecycle { destroy = false }`) | No. `from` cannot name one instance of a `for_each` (`Resource instance keys not allowed`), and the module call stays in the configuration for the other key. | n/a |
| **Lifting `prevent_destroy` for that one key** | Not per key: `prevent_destroy` takes no variables, so it can only be lifted for every key at once. That is what the module does. | Route 53 and the 30-day deletion window (below) |
| **Keeping `prevent_destroy`, retiring by hand** | No. The removal plan fails until someone runs `terraform state rm` on the key, outside review and with write access to state, then schedules the key's deletion in KMS. | `prevent_destroy` |

What guards a key that still signs, without `prevent_destroy`:

- **Terraform deletes a key only after the KSK on it**, because the KSK
  references the key, and the AWS provider deactivates a KSK before deleting it.
- **Route 53 refuses to deactivate a KSK** whose DS record is still at the
  parent (`KeySigningKeyInParentDSRecord`), or that is the only KSK of a zone
  that signs (`KeySigningKeyInUse`). The apply then fails before the key is
  touched. The module refuses the second case at plan already.
- **Deleting the zone**, and with it every key, is refused by the zone's
  `prevent_destroy`, but only in a plan whose configuration still calls the
  module. Terraform reads `prevent_destroy` from the configuration, so removing
  the module call plans the destruction of the zone, its KSKs and its keys.
  Turning signing off is the first step of that plan, and Route 53 refuses it too
  while the parent holds a DS record for one of the zone's KSKs
  (`KeySigningKeyInParentDSRecord`, per the `DisableHostedZoneDNSSEC` API
  reference). Back that up in the pipeline's own policy: deny
  `route53:DeleteHostedZone` there, so that a plan without the module call still
  can't delete the zone.
- **A deleted key is only scheduled for deletion**, 30 days out, and can be
  recovered within that window. The apply that scheduled the deletion also
  removed the key from state, so restoring the map entry alone would create a
  *different* key, whose public key no longer matches the registrar's DS record.
  To recover the original key:

  1. `aws kms cancel-key-deletion --key-id <key ARN>`. This leaves the key
     `Disabled`.
  2. `aws kms enable-key --key-id <key ARN>`.
  3. Restore the map entry, and import the key back at its former address in
     the same apply:

     ```hcl
     import {
       to = module.example_com.module.signing_key["primary"].aws_kms_key.this
       id = "<key ID>"
     }
     ```

  The apply re-creates the alias and the KSK on the original key. That KSK has
  the same public key, so the registrar's DS record matches it again.

What it costs: a key the module no longer manages can't linger by accident, and
a key can't be kept back while its KSK is retired. To keep an old key (say, for
an investigation into its misuse), run `terraform state rm` on it before step 5
and schedule its deletion yourself later.

The pipeline needs Route 53's `DeleteKeySigningKey` and `kms:ScheduleKeyDeletion`
for step 5. If you deny it `kms:ScheduleKeyDeletion` on keys that sign, grant it
for the retirement only: without it the apply deletes the KSK and then fails at
the key, which stays in state until an apply with the grant deletes it.

## Delegating a subdomain

A subdomain such as `test.example.com` can have a zone of its own, usually in
another account than its parent's, so that the account owns its names. The
zone comes from the root module like any other domain's, signed. What
links it to the parent is two records **in the parent zone**, which
`modules/delegation` manages:

- the **NS record**, from the subdomain zone's `name_servers`;
- the **DS record**, from its `ds_records`, which carries the chain of trust
  from the parent down to the subdomain.

`modules/delegation` runs with the **parent's** provider. It is a module of its
own, not a `parent` input on the root module, because the parent is usually in
another account: a root module that wrote into the parent would need a second
provider, and Terraform can't make a provider optional, so every caller would
have to pass one.

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
  providers = { aws = aws.parent } # the parent zone's account

  parent_zone  = module.example_com.zone
  domain_name  = module.test_example_com.zone_name
  name_servers = module.test_example_com.name_servers
  ds_records = {
    primary = module.test_example_com.ds_records["primary"].record
  }
}
```

`examples/subdomain` has both accounts in one configuration. There, the
`ds_records` output waits for the subdomain's signing, so the DS record is never
published for a zone that doesn't sign. When the two zones belong to different
configurations, apply the subdomain's first and carry `name_servers` and the
DS record over as the delegation's inputs.

### Going live

1. **Apply the subdomain's zone.** It signs; nothing resolves through it yet.
2. **Apply the delegation** with the NS record and `ds_records["primary"]`.
   A new name has no older NS or DS records in caches, so both can go in one
   apply, as long as the subdomain zone already signs. Leave `ds_records`
   empty for a delegation without a chain of trust: it resolves, unvalidated.

### Rotating and turning off

The parent does the registrar's part of "Rotating the key-signing key" above,
so each registrar step becomes a change to `ds_records`, in an apply of its own,
with the same waits between them:

| Step | Subdomain zone (`key_signing_keys`) | Parent (`ds_records`) |
|---|---|---|
| 1. Add the new KSK | `{ primary = {}, secondary = {} }` | then add `secondary`, next to `primary` |
| 2. Wait | | the DNSKEY TTL and `ds_ttl`, whichever is longer |
| 3. Remove the old DS record | | `{ secondary = … }`, then wait `ds_ttl` |
| 4. Set the old KSK INACTIVE | `primary = { status = "INACTIVE" }` | |
| 5. Retire the old entry | `{ secondary = {} }` | |

The map names the records rather than following the subdomain's KSKs, because
following them would merge steps 3 and 4 into one apply. Route 53 refuses to
deactivate a KSK whose DS record is still at the parent, and a resolver that
cached the old DS record would fail to validate before its TTL ran out.

`ds_ttl` is an hour by default, so the waits take hours, not the days a TLD's DS
TTL takes. Check the parent's DS record with `dig test.example.com DS
@<one of the parent's name servers>`.

To turn DNSSEC off for the subdomain, empty `ds_records`, wait `ds_ttl`, then
apply `signing_status = "NOT_SIGNING"` on the subdomain's zone.

### What the parent's deploying identity needs

`aws_route53_record` calls `GetHostedZone`, `ChangeResourceRecordSets`,
`GetChange` and `ListResourceRecordSets` (hashicorp/aws 6.73.0). Scope
`ChangeResourceRecordSets` to delegation with its condition keys:
`route53:ChangeResourceRecordSetsRecordTypes` limited to `NS` and `DS`, and
`route53:ChangeResourceRecordSetsNormalizedRecordNames` limited to the
delegated names. The parent zone's own NS record is Route 53's, and the module
refuses to delegate the parent's own name.

## Upgrading from 0.0.1

`key_signing_key_name` became `key_signing_keys`, and the outputs `ds_record`,
`kms_key_arn` and `kms_key_alias` became the maps `ds_records`, `kms_key_arns`
and `kms_key_aliases`, keyed by KSK name. Read the record you gave the registrar
from `ds_records["primary"]`.

The module's `moved` blocks turn 0.0.1's KSK and key into the entry named
`primary`, which is the default and keeps 0.0.1's alias. A caller that did not
set `key_signing_key_name` changes nothing but the version, and the plan shows
three moves and **no** other change (`tests/upgrade.tftest.hcl`).

A caller that set `key_signing_key_name` keeps that name as the map key and moves
on from `primary` in its own configuration, since the module's `moved` blocks
can only name `primary`:

```hcl
module "example_com" {
  # ...
  key_signing_keys = { my_ksk = {} } # was key_signing_key_name = "my_ksk"
}

moved {
  from = module.example_com.aws_route53_key_signing_key.this["primary"]
  to   = module.example_com.aws_route53_key_signing_key.this["my_ksk"]
}

moved {
  from = module.example_com.module.signing_key["primary"]
  to   = module.example_com.module.signing_key["my_ksk"]
}
```

Its key's alias then gains the name, `alias/<label id>-dnssec-myksk` (the label
drops underscores and lowercases), so the plan replaces the alias. The key and the KSK
stay. Whichever case applies, apply only once the plan shows no KSK or key
being created or destroyed.

## Permissions the deploying identity needs

The Route 53 calls these resources make (hashicorp/aws 6.72.0):

| Resource | Calls |
|---|---|
| `aws_route53_zone` | `CreateHostedZone`, `GetChange`, `GetHostedZone`, `ListTagsForResource`, `ChangeTagsForResource`, `UpdateHostedZoneComment` |
| `aws_route53_key_signing_key` | `CreateKeySigningKey`, `ActivateKeySigningKey`, `DeactivateKeySigningKey`, `DeleteKeySigningKey` (retiring a KSK), `GetDNSSEC`, `GetChange` |
| `aws_route53_hosted_zone_dnssec` | `EnableHostedZoneDNSSEC`, `DisableHostedZoneDNSSEC`, `GetDNSSEC`, `GetChange` |

Grant `DeleteHostedZone` to no pipeline. Each KSK's signing key also needs the
usual KMS key-management calls in us-east-1: create the key, set its policy, tag
it, create the alias, and read all of them back; and `kms:ScheduleKeyDeletion`
plus `kms:DeleteAlias` to retire one (see "Retiring a key"). Deny the pipeline
`kms:DisableKey` and `kms:PutKeyPolicy` on keys that already sign a live domain.

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

The tests need Terraform 1.14 or later: before it, test teardown destroys the
mocked zone, which `prevent_destroy` refuses. The module itself needs 1.9.

`tests/zone.tftest.hcl` plans the root module against a mocked provider.
`tests/rotation.tftest.hcl` applies a rotation in sequence (two KSKs, the old
one INACTIVE, then retired) and checks the limits on `key_signing_keys`.
`tests/upgrade.tftest.hcl` applies a snapshot of 0.0.1 (`tests/fixtures/v0.0.1`)
and plans the current module on the same state, so the `moved` blocks are tested
against the addresses 0.0.1 wrote.
`tests/delegation.tftest.hcl` plans the delegation submodule against a mocked
provider and checks the limits on its inputs.
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
| <a name="module_signing_key"></a> [signing\_key](#module\_signing\_key) | ./modules/signing-key | n/a |

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
| <a name="input_key_signing_keys"></a> [key\_signing\_keys](#input\_key\_signing\_keys) | The zone's key-signing keys (KSKs), keyed by KSK name: one, or two during a rotation. Each gets a KMS key of its own. status is ACTIVE (the default) or INACTIVE. Renaming or removing an entry deletes its KSK and schedules its key's deletion: do it only as the last step of a rotation (README.md). Route 53 refuses it while the registrar carries that KSK's DS record. A 0.0.1 KSK becomes the entry named primary. | <pre>map(object({<br/>    status = optional(string, "ACTIVE")<br/>  }))</pre> | <pre>{<br/>  "primary": {}<br/>}</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | Leaf name for this module's label, e.g. the domain without its top-level domain (connectstudios). Becomes the label's name segment and the Name tag. | `string` | n/a | yes |
| <a name="input_signing_status"></a> [signing\_status](#input\_signing\_status) | SIGNING, or NOT\_SIGNING to turn DNSSEC off. Turn it off only after the DS record is gone from the registrar and its TTL has passed: a signed parent pointing at an unsigned zone fails validation for the whole domain. | `string` | `"SIGNING"` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ds_records"></a> [ds\_records](#output\_ds\_records) | The DS record for the registrar, per key-signing key (keyed as key\_signing\_keys), as the record string (key tag, algorithm, digest type, digest) and as its four fields, which registrar forms ask for separately, with the KSK's status. Add a record only once delegation to name\_servers has propagated, and during a rotation only in the order README.md gives. |
| <a name="output_id"></a> [id](#output\_id) | The name the label composed for this module. |
| <a name="output_kms_key_aliases"></a> [kms\_key\_aliases](#output\_kms\_key\_aliases) | Alias of each key-signing key's KMS key (keyed as key\_signing\_keys): alias/<label id>-dnssec for the entry named primary, alias/<label id>-dnssec-<name> for any other. |
| <a name="output_kms_key_arns"></a> [kms\_key\_arns](#output\_kms\_key\_arns) | ARN of each key-signing key's KMS key (keyed as key\_signing\_keys), in us-east-1: for alarms, audits, and the key policy reviews a broken key would call for. |
| <a name="output_label_context"></a> [label\_context](#output\_label\_context) | The context this module's label resolved to, for composing child labels that inherit its naming hierarchy. The leaf name is withheld: the label has a single name slot, so a child that inherited it would compose an id identical to this module's. Child labels must set their own name, and it replaces this one rather than nesting under it, so keep child names unique within the namespace/application hierarchy. |
| <a name="output_name_servers"></a> [name\_servers](#output\_name\_servers) | The four name servers Route 53 assigned the zone, for the registrar's NS records. Delegate to these before adding the DS record. |
| <a name="output_signing_status"></a> [signing\_status](#output\_signing\_status) | The zone's DNSSEC signing status: SIGNING or NOT\_SIGNING. |
| <a name="output_tags"></a> [tags](#output\_tags) | The tags applied to the zone: the label's ohi:* set and Name, merged with extra\_tags. |
| <a name="output_zone"></a> [zone](#output\_zone) | The hosted zone as an object: arn, name and zone\_id. The shape of aws-organization's hostedZone, so a caller can put it straight into its domain\_zones map. |
| <a name="output_zone_id"></a> [zone\_id](#output\_zone\_id) | The hosted zone's id. |
| <a name="output_zone_name"></a> [zone\_name](#output\_zone\_name) | The hosted zone's name: the domain. |
<!-- END_TF_DOCS -->
