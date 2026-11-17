# The signing-key submodule: an asymmetric P-256 signing key in us-east-1 whose
# policy lets Route 53's DNSSEC service use it for this account's zones only.
#
# A real provider with fake credentials, not a mock: the key policy is rendered
# by aws_iam_policy_document, which a mocked provider replaces with random text.
# Plan-only, and the three data sources that would call AWS are overridden, so
# no request leaves the machine.

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock_access_key"
  secret_key                  = "mock_secret_key"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "111111111111"
  }
}

override_data {
  target = data.aws_partition.current
  values = {
    partition = "aws"
  }
}

variables {
  context = {
    namespace   = "vlt"
    region      = "us"
    stage       = "prd"
    aws_region  = "us-east-1"
    application = "platform"
  }
}

run "an_ecc_p256_signing_key_route53_can_use_for_this_account_only" {
  command = plan

  module {
    source = "./modules/signing-key"
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-east-1"
    }
  }

  assert {
    condition = (
      aws_kms_key.this.customer_master_key_spec == "ECC_NIST_P256"
      && aws_kms_key.this.key_usage == "SIGN_VERIFY"
      && aws_kms_key.this.deletion_window_in_days == 30
    )
    error_message = "the key must be an ECC_NIST_P256 SIGN_VERIFY key with a 30-day deletion window"
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/vlt-us-prd-platform-dnssec"
    error_message = "the alias must be alias/<label id>"
  }

  # Route 53's DNSSEC service: exactly DescribeKey, GetPublicKey, Sign and a
  # grant for an AWS resource, and only for this account's hosted zones.
  assert {
    condition = alltrue([
      for s in jsondecode(aws_kms_key.this.policy).Statement : (
        s.Condition.StringEquals["aws:SourceAccount"] == "111111111111"
        && s.Condition.ArnLike["aws:SourceArn"] == "arn:aws:route53:::hostedzone/*"
      ) if try(s.Principal.Service, null) == "dnssec-route53.amazonaws.com"
    ])
    error_message = "every statement for dnssec-route53.amazonaws.com must be limited to this account's hosted zones"
  }

  assert {
    condition = (
      toset(flatten([
        for s in jsondecode(aws_kms_key.this.policy).Statement : s.Action
        if try(s.Principal.Service, null) == "dnssec-route53.amazonaws.com"
      ])) == toset(["kms:DescribeKey", "kms:GetPublicKey", "kms:Sign", "kms:CreateGrant"])
      && length([
        for s in jsondecode(aws_kms_key.this.policy).Statement : s
        if s.Action == "kms:CreateGrant" && try(s.Condition.Bool["kms:GrantIsForAWSResource"], null) == "true"
      ]) == 1
    )
    error_message = "Route 53's DNSSEC service may only describe, read the public key, sign, and create grants for AWS resources"
  }

  assert {
    condition = length([
      for s in jsondecode(aws_kms_key.this.policy).Statement : s
      if s.Action == "kms:*" && try(s.Principal.AWS, null) == "arn:aws:iam::111111111111:root"
    ]) == 1
    error_message = "the account's own IAM must administer the key, as in KMS's default policy"
  }
}

run "a_key_outside_us_east_1_is_refused" {
  command = plan

  module {
    source = "./modules/signing-key"
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-west-2"
    }
  }

  expect_failures = [aws_kms_key.this]
}
