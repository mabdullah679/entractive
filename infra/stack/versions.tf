terraform {
  required_version = ">= 1.10"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.80" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
  backend "s3" {
    bucket       = "pf-entractive-tfstate-346208529954"
    key          = "stack/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region              = "ap-southeast-2"
  allowed_account_ids = ["346208529954"]
  default_tags {
    tags = {
      project      = "portfolio"
      repo         = "entractive"
      "managed-by" = "terraform"
    }
  }
}
