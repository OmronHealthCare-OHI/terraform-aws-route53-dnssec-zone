terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

# The caller owns the label: it states where it deploys and where it sits in the
# ohi:* hierarchy, and hands the resolved context to every module it calls.
module "label" {
  source = "github.com/OmronHealthCare-OHI/terraform-null-label?ref=1.0.0"

  namespace  = "vlt"
  region     = "us"
  stage      = "prd"
  aws_region = "us-west-2" # tag only; not part of the id

  application = "platform"
  module      = "dns" # -> ohi:module = platform-dns; not in the id
  owner       = "cloud-foundations"

  tags = {
    managed-by = "terraform"
  }
}

# The caller's own region, for whatever else it manages.
provider "aws" {
  region              = "us-west-2"
  allowed_account_ids = ["111111111111"]

  default_tags {
    tags = module.label.tags
  }
}

# Route 53 accepts DNSSEC signing keys from us-east-1 only, and each zone
# creates its own key, so the zones get a us-east-1 provider. Route 53 itself is
# global: the zones don't care which region manages them.
provider "aws" {
  alias               = "us_east_1"
  region              = "us-east-1"
  allowed_account_ids = ["111111111111"]

  default_tags {
    tags = module.label.tags
  }
}

# Two zones, each with keys of its own. example.com is mid-rotation: a second
# key-signing key, on a second KMS key, next to the first (README.md, "Rotating
# the key-signing key"). Outside a rotation a zone has one, primary by default.
module "example_com" {
  source = "../.."
  providers = {
    aws = aws.us_east_1
  }

  name        = "example"
  domain_name = "example.com"
  key_signing_keys = {
    primary   = { status = "ACTIVE" }
    secondary = { status = "ACTIVE" }
  }
  signing_status = "SIGNING"
  comment        = "Public DNS for example.com"
  context        = module.label.context

  extra_tags = {
    cost-centre = "platform"
  }
}

module "example_org" {
  source = "../.."
  providers = {
    aws = aws.us_east_1
  }

  name        = "example-org"
  domain_name = "example.org"
  context     = module.label.context
}

# Chaining: a child label inherits the module's hierarchy and sets its own leaf
# name, so sibling resources stay under one namespace/application.
module "child_label" {
  source = "github.com/OmronHealthCare-OHI/terraform-null-label?ref=1.0.0"

  context = module.example_com.label_context
  name    = "records"
}

output "example_com_zone" {
  description = "example.com's zone in aws-organization's hostedZone shape, ready for its domain_zones map"
  value       = module.example_com.zone
}

output "example_com_name_servers" {
  description = "The name servers to delegate example.com to at the registrar"
  value       = module.example_com.name_servers
}

output "example_com_kms_key_arns" {
  description = "example.com's signing keys, one per key-signing key, for alarms and audits"
  value       = module.example_com.kms_key_arns
}

output "example_com_ds_records" {
  description = "example.com's DS records for the registrar, one per key-signing key"
  value       = module.example_com.ds_records
}

output "child_id" {
  description = "Name a child label composes from the module's exported context"
  value       = module.child_label.id
}
