# Upgrading from 0.0.1 keeps the zone's KSK and its KMS key: the moved blocks in
# main.tf turn 0.0.1's single, unkeyed resources into the entry named primary.
#
# The first run applies 0.0.1 itself (a snapshot in fixtures/v0.0.1), the second
# plans the current module on the same state (state_key, Terraform 1.11+). If a
# moved block were missing, the KSK would plan as created, so its key tag and
# key ARN would be unknown or new, and the assertions fail. Removing either
# moved block makes this file fail; that is the check that it tests anything.
#
# Mocked as in zone.tftest.hcl, for the same reasons.
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Deny\",\"Action\":\"*\",\"Resource\":\"*\"}]}"
    }
  }
}

variables {
  name        = "example"
  domain_name = "example.com"

  context = {
    namespace   = "vlt"
    region      = "us"
    stage       = "prd"
    aws_region  = "us-west-2"
    application = "platform"
  }
}

run "a_zone_applied_with_0_0_1" {
  command   = apply
  state_key = "zone"

  module {
    source = "./tests/fixtures/v0.0.1"
  }

  override_resource {
    target = aws_route53_zone.this
    values = {
      zone_id = "Z0123456789ABCDEFGHIJ"
    }
  }

  override_resource {
    target = module.signing_key.aws_kms_key.this
    values = {
      arn    = "arn:aws:kms:us-east-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
      key_id = "1234abcd-12ab-34cd-56ef-1234567890ab"
    }
  }

  override_resource {
    target = aws_route53_key_signing_key.this
    values = {
      ds_record              = "12345 13 2 ABCDEF0123456789"
      key_tag                = 12345
      signing_algorithm_type = 13
      digest_algorithm_type  = 2
      digest_value           = "ABCDEF0123456789"
    }
  }
}

# The default key_signing_keys, { primary = {} }: what a 0.0.1 caller that never
# set key_signing_key_name gets by changing nothing but the version.
run "the_upgrade_keeps_the_ksk_and_its_key" {
  command   = plan
  state_key = "zone"

  assert {
    condition = (
      aws_route53_key_signing_key.this["primary"].key_tag == run.a_zone_applied_with_0_0_1.ds_record.key_tag
      && aws_route53_key_signing_key.this["primary"].name == "primary"
    )
    error_message = "the 0.0.1 KSK must become the entry named primary, not be replaced"
  }

  assert {
    condition = (
      output.ds_records["primary"].record == run.a_zone_applied_with_0_0_1.ds_record.record
      && output.kms_key_arns["primary"] == run.a_zone_applied_with_0_0_1.kms_key_arn
      && output.kms_key_aliases["primary"] == run.a_zone_applied_with_0_0_1.kms_key_alias
    )
    error_message = "the upgrade must keep the KSK's DS record, its KMS key and the key's alias"
  }
}
