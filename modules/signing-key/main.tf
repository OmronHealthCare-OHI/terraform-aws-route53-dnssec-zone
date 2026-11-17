# The KMS key one Route 53 key-signing key (KSK) signs with. The root module
# calls this once per KSK: Route 53 requires each of a zone's KSKs to use a
# different KMS key.
#
# Route 53 requires an asymmetric ECC_NIST_P256 SIGN_VERIFY key in us-east-1,
# whatever region the zones are managed from, so this module checks the
# provider's region rather than trusting the caller's.
#
# Once a registrar carries a DS record for a zone signed by this key, the key
# keeps that domain resolving: disabled, scheduled for deletion, or with
# Route 53 dropped from its policy, every validating resolver fails the whole
# domain. Hence the longest deletion window by default, so a scheduled deletion
# can be cancelled.
#
# No prevent_destroy, so that a rotation can retire a key with a reviewed
# apply. prevent_destroy cannot be set per key (it takes no variables), and a
# removed block cannot name one of a for_each's instances, so the only other
# way out would be a hand-run `terraform state rm`. Terraform destroys a key
# only after the KSK on it, which the provider deactivates first, and Route 53
# refuses that while the KSK's DS record is at the parent, or while it is the
# only KSK of a zone that signs (README.md, "Retiring a key").

module "label" {
  source = "github.com/OmronHealthCare-OHI/terraform-null-label?ref=1.0.0"

  context = var.context
  name    = var.name
  tags    = var.extra_tags
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Route 53 may use this key for one zone in this account only: the
  # confused-deputy guard AWS recommends for service principals, as narrow as
  # one key per zone allows.
  route53_source_conditions = [
    {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    },
    {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:route53:::hostedzone/${var.hosted_zone_id}"]
    },
  ]
}

data "aws_iam_policy_document" "key" {
  #checkov:skip=CKV_AWS_111: A key policy: "*" is this key, and the writes are the account root's, as in KMS's default key policy, or Route 53's, limited to this account's zones.
  #checkov:skip=CKV_AWS_356: A key policy: "*" as the resource means this key and nothing else.
  #checkov:skip=CKV_AWS_109: The account root administers its own key, as in KMS's default key policy; without it the key can become unmanageable.
  # The account's own IAM decides who administers and uses the key, as in
  # KMS's default key policy. Without it the key can become unmanageable.
  statement {
    sid       = "EnableIamPolicies"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "AllowRoute53DnssecService"
    effect    = "Allow"
    actions   = ["kms:DescribeKey", "kms:GetPublicKey", "kms:Sign"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["dnssec-route53.amazonaws.com"]
    }

    dynamic "condition" {
      for_each = local.route53_source_conditions
      content {
        test     = condition.value.test
        variable = condition.value.variable
        values   = condition.value.values
      }
    }
  }

  statement {
    sid       = "AllowRoute53DnssecToCreateGrant"
    effect    = "Allow"
    actions   = ["kms:CreateGrant"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["dnssec-route53.amazonaws.com"]
    }

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }

    dynamic "condition" {
      for_each = local.route53_source_conditions
      content {
        test     = condition.value.test
        variable = condition.value.variable
        values   = condition.value.values
      }
    }
  }
}

resource "aws_kms_key" "this" {
  description              = "DNSSEC key-signing key for a Route 53 hosted zone (${module.label.id})"
  customer_master_key_spec = "ECC_NIST_P256"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = var.deletion_window_in_days
  policy                   = data.aws_iam_policy_document.key.json

  tags = module.label.tags

  lifecycle {
    precondition {
      condition     = data.aws_region.current.region == "us-east-1"
      error_message = "Route 53 accepts DNSSEC signing keys from us-east-1 only: pass this module a provider configured for us-east-1."
    }
  }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${module.label.id}"
  target_key_id = aws_kms_key.this.key_id
}
