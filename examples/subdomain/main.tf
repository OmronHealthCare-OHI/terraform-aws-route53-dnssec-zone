terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

# A subdomain with a zone of its own, in another account than its parent:
# test.example.com in a test account, delegated from example.com in the account
# that holds the organization's domains. The subdomain's zone is signed like any
# other; the parent publishes its NS and DS records.
#
# Both zones are in this one configuration to show the wiring. Where they belong
# to different configurations (the usual case), apply the subdomain's first and
# carry name_servers and the DS record over as the delegation's inputs.

module "label" {
  source = "github.com/OmronHealthCare-OHI/terraform-null-label?ref=1.0.0"

  namespace  = "vlt"
  region     = "us"
  stage      = "dev"
  aws_region = "us-east-1" # tag only; not part of the id

  application = "platform"
  module      = "dns"
  owner       = "cloud-foundations"
}

# Two accounts, so two sets of credentials. Both providers start from the same
# caller credentials and each assumes a role in its own account; the role names
# here are placeholders for the roles your pipeline deploys with.
# allowed_account_ids does not pick an account, it only refuses a wrong one.

# The parent zone's account. Route 53 is global, so the region only has to be
# one the provider accepts; us-east-1 also lets it create the parent's keys.
provider "aws" {
  alias               = "parent"
  region              = "us-east-1"
  allowed_account_ids = ["111111111111"]

  assume_role {
    role_arn = "arn:aws:iam::111111111111:role/dns-deployer"
  }
}

# The subdomain's account, in us-east-1 for its DNSSEC signing key.
provider "aws" {
  alias               = "test_us_east_1"
  region              = "us-east-1"
  allowed_account_ids = ["222222222222"]

  assume_role {
    role_arn = "arn:aws:iam::222222222222:role/dns-deployer"
  }
}

module "example_com" {
  source = "../.."
  providers = {
    aws = aws.parent
  }

  name        = "example"
  domain_name = "example.com"
  context     = module.label.context
}

module "test_example_com" {
  source = "../.."
  providers = {
    aws = aws.test_us_east_1
  }

  name        = "example-test"
  domain_name = "test.example.com"
  context     = module.label.context
}

# The NS and DS records in example.com, so with the parent's provider. The DS
# record is named, not derived from the subdomain's keys: during a rotation,
# each change to this map is a step of its own (README.md, "Delegating a
# subdomain"). ds_records waits for the subdomain's signing resource, but that
# resource exists with NOT_SIGNING too, so the DS record is published only while
# the subdomain's zone signs.
module "test_example_com_delegation" {
  source = "../../modules/delegation"
  providers = {
    aws = aws.parent
  }

  parent_zone  = module.example_com.zone
  domain_name  = module.test_example_com.zone_name
  name_servers = module.test_example_com.name_servers
  ds_records = module.test_example_com.signing_status == "SIGNING" ? {
    primary = module.test_example_com.ds_records["primary"].record
  } : {}
}

output "example_com_name_servers" {
  description = "The name servers to delegate example.com to at the registrar"
  value       = module.example_com.name_servers
}

output "test_example_com_delegation" {
  description = "What example.com publishes for test.example.com"
  value = {
    fqdn         = module.test_example_com_delegation.fqdn
    name_servers = module.test_example_com_delegation.name_servers
    ds_records   = module.test_example_com_delegation.ds_records
  }
}
