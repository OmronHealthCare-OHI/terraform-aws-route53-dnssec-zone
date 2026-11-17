# The zone module: a public zone, one ACTIVE key-signing key on the caller's
# KMS key, and signing on, tagged from the label.
#
# `command = plan` with a mocked provider needs no credentials. The outputs
# carry values AWS assigns at apply, so the run that checks them overrides the
# zone and the KSK with values in AWS's formats.

mock_provider "aws" {}

variables {
  name        = "example"
  domain_name = "example.com"
  kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  context = {
    namespace   = "vlt"
    region      = "us"
    stage       = "prd"
    aws_region  = "us-west-2"
    application = "platform"
  }
}

run "a_public_zone_signed_by_one_active_key" {
  command = plan

  assert {
    condition     = aws_route53_zone.this.name == "example.com" && length(aws_route53_zone.this.vpc) == 0
    error_message = "the zone must be the domain, and public: no vpc block"
  }

  assert {
    condition     = aws_route53_zone.this.comment == "Public DNS for example.com, signed with DNSSEC"
    error_message = "the default comment must name the domain"
  }

  assert {
    condition     = aws_route53_zone.this.tags["ohi:application"] == "platform" && aws_route53_zone.this.tags["Name"] == output.id
    error_message = "the zone must carry the label's tags"
  }

  assert {
    condition = (
      aws_route53_key_signing_key.this.key_management_service_arn == var.kms_key_arn
      && aws_route53_key_signing_key.this.name == "primary"
      && aws_route53_key_signing_key.this.status == "ACTIVE"
    )
    error_message = "the zone must have one ACTIVE key-signing key, named primary by default, on the caller's KMS key"
  }

  assert {
    condition     = aws_route53_hosted_zone_dnssec.this.signing_status == "SIGNING"
    error_message = "signing must be on by default"
  }
}

run "signing_can_be_turned_off" {
  command = plan

  variables {
    signing_status = "NOT_SIGNING"
    comment        = "Example"
  }

  assert {
    condition     = aws_route53_hosted_zone_dnssec.this.signing_status == "NOT_SIGNING" && aws_route53_zone.this.comment == "Example"
    error_message = "signing_status and comment must reach the resources"
  }
}

run "outputs_carry_the_zone_and_the_ds_record" {
  command = apply

  override_resource {
    target = aws_route53_zone.this
    values = {
      zone_id      = "Z0123456789ABCDEFGHIJ"
      arn          = "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
      name_servers = ["ns-1.awsdns-01.com", "ns-2.awsdns-02.net", "ns-3.awsdns-03.org", "ns-4.awsdns-04.co.uk"]
    }
  }

  override_resource {
    target = aws_route53_key_signing_key.this
    values = {
      hosted_zone_id         = "Z0123456789ABCDEFGHIJ"
      ds_record              = "12345 13 2 ABCDEF0123456789"
      key_tag                = 12345
      signing_algorithm_type = 13
      digest_algorithm_type  = 2
      digest_value           = "ABCDEF0123456789"
    }
  }

  # The shape aws-organization publishes as <name>_domain_zone.
  assert {
    condition = (
      output.zone == {
        arn     = "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
        name    = "example.com"
        zone_id = "Z0123456789ABCDEFGHIJ"
      }
      && output.zone_id == output.zone.zone_id
      && output.zone_name == output.zone.name
    )
    error_message = "zone must be exactly arn, name and zone_id, and the flattenings must equal its fields"
  }

  assert {
    condition     = length(output.name_servers) == 4
    error_message = "name_servers must carry the zone's four name servers"
  }

  assert {
    condition = output.ds_record == {
      record      = "12345 13 2 ABCDEF0123456789"
      key_tag     = 12345
      algorithm   = 13
      digest_type = 2
      digest      = "ABCDEF0123456789"
    }
    error_message = "ds_record must carry the record and its four fields"
  }
}

run "an_uppercase_domain_is_rejected" {
  command = plan

  variables {
    domain_name = "Example.com"
  }

  expect_failures = [var.domain_name]
}

run "a_trailing_dot_is_rejected" {
  command = plan

  variables {
    domain_name = "example.com."
  }

  expect_failures = [var.domain_name]
}

run "a_single_label_domain_is_rejected" {
  command = plan

  variables {
    domain_name = "localhost"
  }

  expect_failures = [var.domain_name]
}

# Internationalized domains in their ASCII (Punycode) form, the top-level
# label included.
run "a_punycode_domain_is_accepted" {
  command = plan

  variables {
    domain_name = "xn--e1afmkfd.xn--p1ai"
  }

  assert {
    condition     = aws_route53_zone.this.name == "xn--e1afmkfd.xn--p1ai"
    error_message = "a Punycode domain, its top-level label included, must be accepted"
  }
}

run "an_empty_punycode_top_level_label_is_rejected" {
  command = plan

  variables {
    domain_name = "example.xn--"
  }

  expect_failures = [var.domain_name]
}

run "a_numeric_top_level_label_is_rejected" {
  command = plan

  variables {
    domain_name = "example.123"
  }

  expect_failures = [var.domain_name]
}

run "a_key_outside_us_east_1_is_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-west-2:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  expect_failures = [var.kms_key_arn]
}

run "a_key_alias_is_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:111111111111:alias/dnssec"
  }

  expect_failures = [var.kms_key_arn]
}

run "a_multi_region_key_is_accepted" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/mrk-1234abcd12ab34cd56ef1234567890ab"
  }

  assert {
    condition     = aws_route53_key_signing_key.this.key_management_service_arn == var.kms_key_arn
    error_message = "a multi-region key ARN must be accepted"
  }
}

run "a_short_key_signing_key_name_is_rejected" {
  command = plan

  variables {
    key_signing_key_name = "ab"
  }

  expect_failures = [var.key_signing_key_name]
}

run "an_unknown_signing_status_is_rejected" {
  command = plan

  variables {
    signing_status = "OFF"
  }

  expect_failures = [var.signing_status]
}
