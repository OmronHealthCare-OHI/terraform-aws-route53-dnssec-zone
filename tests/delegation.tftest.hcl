# The delegation submodule: the NS and DS records a parent zone holds for a
# subdomain with a zone of its own, and the limits on its inputs.
#
# `command = plan` with a mocked provider needs no credentials. Every value
# asserted on comes from the inputs, so nothing AWS assigns is needed.

mock_provider "aws" {}

variables {
  parent_zone = {
    name    = "example.com"
    zone_id = "Z0123456789ABCDEFGHIJ"
  }
  domain_name = "test.example.com"
  name_servers = [
    "ns-1.awsdns-01.org",
    "ns-2.awsdns-02.co.uk",
    "ns-3.awsdns-03.com",
    "ns-4.awsdns-04.net",
  ]
  ds_records = {
    primary = "12345 13 2 0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF"
  }
}

run "the_parent_delegates_with_ns_and_ds" {
  command = plan

  module {
    source = "./modules/delegation"
  }

  assert {
    condition = (
      aws_route53_record.ns.zone_id == "Z0123456789ABCDEFGHIJ"
      && aws_route53_record.ns.name == "test.example.com"
      && aws_route53_record.ns.type == "NS"
      && aws_route53_record.ns.ttl == 172800
    )
    error_message = "the NS record must sit in the parent zone at the subdomain, with a two-day TTL by default"
  }

  assert {
    condition     = output.name_servers == toset(var.name_servers)
    error_message = "the NS record must name the subdomain zone's name servers"
  }

  assert {
    condition = (
      length(aws_route53_record.ds) == 1
      && aws_route53_record.ds[0].zone_id == "Z0123456789ABCDEFGHIJ"
      && aws_route53_record.ds[0].name == "test.example.com"
      && aws_route53_record.ds[0].type == "DS"
      && aws_route53_record.ds[0].ttl == 3600
    )
    error_message = "the DS record must sit next to the NS record, with an hour's TTL by default"
  }

  assert {
    condition     = aws_route53_record.ds[0].records == toset(values(var.ds_records))
    error_message = "the DS record must hold the record given"
  }

  assert {
    condition     = output.ds_records == var.ds_records
    error_message = "ds_records must report the published records"
  }
}

run "without_ds_records_the_delegation_has_no_chain_of_trust" {
  command = plan

  module {
    source = "./modules/delegation"
  }

  variables {
    ds_records = {}
  }

  assert {
    condition     = length(aws_route53_record.ds) == 0
    error_message = "no DS record set may be planned when none is published"
  }

  assert {
    condition     = aws_route53_record.ns.type == "NS"
    error_message = "the NS record must still be planned"
  }

  assert {
    condition     = length(output.ds_records) == 0
    error_message = "ds_records must report nothing published"
  }
}

run "a_rotation_publishes_both_ds_records_in_one_record_set" {
  command = plan

  module {
    source = "./modules/delegation"
  }

  variables {
    ds_records = {
      primary   = "12345 13 2 0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF"
      secondary = "54321 13 2 FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210"
    }
    ns_ttl = 3600
    ds_ttl = 300
  }

  assert {
    condition     = length(aws_route53_record.ds) == 1 && length(aws_route53_record.ds[0].records) == 2
    error_message = "both DS records must be in one record set"
  }

  assert {
    condition     = aws_route53_record.ns.ttl == 3600 && aws_route53_record.ds[0].ttl == 300
    error_message = "the TTLs must follow ns_ttl and ds_ttl"
  }
}

run "a_parent_name_with_a_trailing_dot_is_accepted" {
  command = plan

  module {
    source = "./modules/delegation"
  }

  variables {
    parent_zone = {
      name    = "Example.com."
      zone_id = "Z0123456789ABCDEFGHIJ"
    }
  }

  assert {
    condition     = aws_route53_record.ns.name == "test.example.com"
    error_message = "a parent name as DNS writes it (a trailing dot, any case) must still match"
  }
}

run "a_name_outside_the_parent_is_rejected" {
  command = plan

  module {
    source = "./modules/delegation"
  }

  variables {
    domain_name = "test.example.org"
  }

  expect_failures = [var.domain_name]
}

run "a_name_that_only_ends_in_the_parent_name_is_rejected" {
  command = plan

  module {
    source = "./modules/delegation"
  }

  variables {
    domain_name = "testexample.com"
  }

  expect_failures = [var.domain_name]
}

run "the_parent_itself_is_rejected" {
  command = plan

  module {
    source = "./modules/delegation"
  }

  variables {
    domain_name = "example.com"
  }

  expect_failures = [var.domain_name]
}

run "a_malformed_parent_zone_id_is_rejected" {
  command = plan

  module {
    source = "./modules/delegation"
  }

  variables {
    parent_zone = {
      name    = "example.com"
      zone_id = "example.com"
    }
  }

  expect_failures = [var.parent_zone]
}

run "no_name_servers_are_rejected" {
  command = plan

  module {
    source = "./modules/delegation"
  }

  variables {
    name_servers = []
  }

  expect_failures = [var.name_servers]
}

run "a_name_server_with_a_trailing_dot_is_rejected" {
  command = plan

  module {
    source = "./modules/delegation"
  }

  variables {
    name_servers = ["ns-1.awsdns-01.org."]
  }

  expect_failures = [var.name_servers]
}

run "a_malformed_ds_record_is_rejected" {
  command = plan

  module {
    source = "./modules/delegation"
  }

  variables {
    ds_records = {
      primary = "12345 13 2 not-a-digest"
    }
  }

  expect_failures = [var.ds_records]
}

run "three_ds_records_are_rejected" {
  command = plan

  module {
    source = "./modules/delegation"
  }

  variables {
    ds_records = {
      one   = "11111 13 2 0123456789ABCDEF"
      two   = "22222 13 2 0123456789ABCDEF"
      three = "33333 13 2 0123456789ABCDEF"
    }
  }

  expect_failures = [var.ds_records]
}

run "the_same_ds_record_twice_is_rejected" {
  command = plan

  module {
    source = "./modules/delegation"
  }

  variables {
    ds_records = {
      primary   = "12345 13 2 0123456789ABCDEF"
      secondary = "12345 13 2 0123456789ABCDEF"
    }
  }

  expect_failures = [var.ds_records]
}

run "a_ttl_below_a_minute_is_rejected" {
  command = plan

  module {
    source = "./modules/delegation"
  }

  variables {
    ds_ttl = 30
  }

  expect_failures = [var.ds_ttl]
}
