# The KMS key Route 53 signs DNSSEC zones with: one per account, shared by
# every zone the root module creates there.
#
# Route 53 requires an asymmetric ECC_NIST_P256 SIGN_VERIFY key in us-east-1,
# whatever region the zones are managed from, so this module checks the
# provider's region rather than trusting the caller's.
#
# Once a registrar carries a DS record for a zone signed by this key, the key
# keeps that domain resolving: disabled, scheduled for deletion, or with
# Route 53 dropped from its policy, every validating resolver fails the whole
# domain. Hence prevent_destroy, and the longest deletion window.

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

  # Route 53 calls KMS for this account's zones only (the confused-deputy
  # guard AWS recommends for service principals).
  route53_source_conditions = [
    {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    },
    {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:route53:::hostedzone/*"]
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
  description              = "DNSSEC key-signing keys for Route 53 hosted zones in this account (${module.label.id})"
  customer_master_key_spec = "ECC_NIST_P256"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = var.deletion_window_in_days
  policy                   = data.aws_iam_policy_document.key.json

  tags = module.label.tags

  lifecycle {
    prevent_destroy = true

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
