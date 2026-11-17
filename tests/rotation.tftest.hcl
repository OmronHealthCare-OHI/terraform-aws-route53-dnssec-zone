# Rotating the key-signing key (KSK) by AWS's double-DS method: a second KSK on
# a KMS key of its own, then retiring the first, INACTIVE before it goes. And
# the limits on key_signing_keys.
#
# The retirement runs apply in sequence on one state, so they also test the
# choice the module made for retiring a key: its KMS key has no prevent_destroy.
# With it, the last run's plan would fail ("Instance cannot be destroyed"),
# and expect_failures cannot catch that. Route 53's own guards (no deactivating
# a KSK whose DS record is at the parent, or a signing zone's only KSK) are AWS
# behaviour a mocked provider doesn't have; README.md cites them.
#
# Mocked as in zone.tftest.hcl, for the same reasons. The runs apply, so the
# values AWS assigns are overridden in its formats: the submodule validates the
# zone id, and the provider the key ARNs.
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

override_resource {
  target = aws_route53_zone.this
  values = {
    zone_id = "Z0123456789ABCDEFGHIJ"
  }
}

override_resource {
  target = module.signing_key["primary"].aws_kms_key.this
  values = {
    arn    = "arn:aws:kms:us-east-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    key_id = "1234abcd-12ab-34cd-56ef-1234567890ab"
  }
}

override_resource {
  target = module.signing_key["secondary"].aws_kms_key.this
  values = {
    arn    = "arn:aws:kms:us-east-1:111111111111:key/5678abcd-56ab-78cd-90ef-5678901234ab"
    key_id = "5678abcd-56ab-78cd-90ef-5678901234ab"
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

# Step 1 of a rotation: a second ACTIVE KSK, on a second KMS key.
run "a_second_key_signing_key_gets_a_kms_key_of_its_own" {
  command = apply

  variables {
    key_signing_keys = {
      primary   = {}
      secondary = {}
    }
  }

  assert {
    condition = (
      toset(keys(aws_route53_key_signing_key.this)) == toset(["primary", "secondary"])
      && alltrue([for name, ksk in aws_route53_key_signing_key.this : ksk.name == name && ksk.status == "ACTIVE"])
    )
    error_message = "each entry must become an ACTIVE KSK named after its key"
  }

  assert {
    condition = (
      alltrue([for name, ksk in aws_route53_key_signing_key.this : ksk.key_management_service_arn == output.kms_key_arns[name]])
      && output.kms_key_arns["primary"] != output.kms_key_arns["secondary"]
    )
    error_message = "each KSK must sign with its own KMS key: Route 53 refuses two KSKs on one key"
  }

  assert {
    condition = output.kms_key_aliases == {
      primary   = "alias/vlt-us-prd-platform-example-dnssec"
      secondary = "alias/vlt-us-prd-platform-example-dnssec-secondary"
    }
    error_message = "the primary entry keeps 0.0.1's alias, and any other entry adds its name"
  }

  assert {
    condition     = toset(keys(output.ds_records)) == toset(["primary", "secondary"])
    error_message = "ds_records must carry a DS record per KSK, keyed as key_signing_keys"
  }

  assert {
    condition     = aws_route53_hosted_zone_dnssec.this.signing_status == "SIGNING"
    error_message = "signing must stay on throughout a rotation"
  }
}

# Step 4, first half: once the old DS record is gone from the registrar and its
# TTL has passed, the old KSK goes INACTIVE, and the zone signs with the other.
run "the_old_key_signing_key_goes_inactive_first" {
  command = apply

  variables {
    key_signing_keys = {
      primary   = { status = "INACTIVE" }
      secondary = {}
    }
  }

  assert {
    condition = (
      aws_route53_key_signing_key.this["primary"].status == "INACTIVE"
      && aws_route53_key_signing_key.this["secondary"].status == "ACTIVE"
      && output.ds_records["primary"].status == "INACTIVE"
    )
    error_message = "status must reach the KSK and the ds_records output"
  }
}

# Step 4, second half: removing the entry deletes the INACTIVE KSK and its key,
# in a plain apply, with no state surgery.
run "the_inactive_entry_is_retired_with_its_kms_key" {
  command = apply

  variables {
    key_signing_keys = {
      secondary = {}
    }
  }

  assert {
    condition = (
      toset(keys(aws_route53_key_signing_key.this)) == toset(["secondary"])
      && toset(keys(output.kms_key_arns)) == toset(["secondary"])
      && toset(keys(output.ds_records)) == toset(["secondary"])
    )
    error_message = "the retired entry's KSK, key and DS record must be gone, and the other entry's kept"
  }
}

run "three_key_signing_keys_are_rejected" {
  command = plan

  variables {
    key_signing_keys = {
      primary   = {}
      secondary = {}
      tertiary  = {}
    }
  }

  expect_failures = [var.key_signing_keys]
}

run "no_key_signing_key_is_rejected" {
  command = plan

  variables {
    key_signing_keys = {}
  }

  expect_failures = [var.key_signing_keys]
}

run "a_short_key_signing_key_name_is_rejected" {
  command = plan

  variables {
    key_signing_keys = {
      ab = {}
    }
  }

  expect_failures = [var.key_signing_keys]
}

# The label lowercases and drops underscores, so these would ask for one alias.
run "names_that_compose_one_alias_are_rejected" {
  command = plan

  variables {
    key_signing_keys = {
      next_key = {}
      NextKey  = {}
    }
  }

  expect_failures = [var.key_signing_keys]
}

# The other entry stays ACTIVE, so only the status rule can fail.
run "an_unknown_key_signing_key_status_is_rejected" {
  command = plan

  variables {
    key_signing_keys = {
      primary   = {}
      secondary = { status = "DELETED" }
    }
  }

  expect_failures = [var.key_signing_keys]
}

# Route 53 refuses to deactivate a signing zone's only KSK.
run "a_signing_zone_without_an_active_key_is_rejected" {
  command = plan

  variables {
    key_signing_keys = {
      primary   = { status = "INACTIVE" }
      secondary = { status = "INACTIVE" }
    }
  }

  expect_failures = [var.key_signing_keys]
}

# Turning DNSSEC off: signing off first, then the KSK may go INACTIVE.
run "a_zone_that_does_not_sign_may_have_no_active_key" {
  command = plan

  variables {
    signing_status = "NOT_SIGNING"
    key_signing_keys = {
      primary = { status = "INACTIVE" }
    }
  }

  assert {
    condition     = aws_route53_key_signing_key.this["primary"].status == "INACTIVE"
    error_message = "a zone that does not sign may keep its KSK INACTIVE"
  }
}
