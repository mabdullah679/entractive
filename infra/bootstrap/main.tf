# Bootstrap: the pieces that must exist BEFORE the pipeline can run.
#   - Terraform state bucket (versioned, encrypted, native S3 lockfile)
#   - ECR repository for the resource-server image (the image is pushed before
#     the main stack is applied, so the repo cannot live inside that stack)
#   - SSM parameters holding the Entra IDs (placeholders until the owner sets them)
#   - Two GitHub-OIDC roles: read-only "plan" and scoped "apply"
# Applied by hand ONCE (local state, deliberately not in S3: it creates the bucket).
# Destroy this LAST, after the main stack is gone: `terraform destroy` here.
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.80" }
  }
}

variable "name_prefix" {
  type    = string
  default = "pf-entractive"
}
variable "github_repo" {
  type    = string
  default = "mabdullah679/entractive"
}
# GitHub now issues IMMUTABLE, ID-qualified subjects for this repo
# (repo:<owner>@<owner-id>/<repo>@<repo-id>:...), observed from a real run's
# token. Trusting the IDs means a deleted-and-recreated repo with the same
# name cannot assume these roles.
variable "github_subject_repo" {
  type    = string
  default = "mabdullah679@131607929/entractive@1391818797"
}
variable "github_branch" {
  type    = string
  default = "prod-hardening"
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

data "aws_caller_identity" "me" {}
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  account_id   = data.aws_caller_identity.me.account_id
  boundary_arn = "arn:aws:iam::${local.account_id}:policy/portfolio-ci-boundary"
  ssm_prefix   = "/${var.name_prefix}"
}

# ---- state bucket ----------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket        = "${var.name_prefix}-tfstate-${local.account_id}"
  force_destroy = true # teardown must be one command; state is disposable with the stack
}
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---- ECR ---------------------------------------------------------------------
resource "aws_ecr_repository" "api" {
  name                 = "${var.name_prefix}-resource-server"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
}
resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep last 5 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 5 }
      action       = { type = "expire" }
    }]
  })
}

# ---- Entra IDs in SSM --------------------------------------------------------
# Values are placeholders on first create and then OWNED BY THE OPERATOR:
#   aws ssm put-parameter --name /pf-entractive/tenant-id --type String --overwrite --value <id>
# ignore_changes means Terraform never reverts them. No code change is needed
# to point the deployed stack at a real tenant; re-run the pipeline afterwards.
resource "aws_ssm_parameter" "entra" {
  for_each = toset(["tenant-id", "spa-client-id", "api-client-id", "api-scope"])
  name     = "${local.ssm_prefix}/${each.key}"
  type     = "String"
  value    = "PLACEHOLDER-not-configured"
  lifecycle { ignore_changes = [value] }
}

# ---- GitHub OIDC roles -------------------------------------------------------
locals {
  sub_branch = "repo:${var.github_subject_repo}:ref:refs/heads/${var.github_branch}"
  sub_pr     = "repo:${var.github_subject_repo}:pull_request"
}

data "aws_iam_policy_document" "trust_apply" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.sub_branch]
    }
  }
}

data "aws_iam_policy_document" "trust_plan" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.sub_branch, local.sub_pr]
    }
  }
}

resource "aws_iam_role" "apply" {
  name                 = "${var.name_prefix}-gha-apply"
  assume_role_policy   = data.aws_iam_policy_document.trust_apply.json
  permissions_boundary = local.boundary_arn
  max_session_duration = 3600
}

resource "aws_iam_role" "plan" {
  name                 = "${var.name_prefix}-gha-plan"
  assume_role_policy   = data.aws_iam_policy_document.trust_plan.json
  permissions_boundary = local.boundary_arn
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "state_rw" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.state.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}
resource "aws_iam_role_policy" "plan_state" {
  name   = "state-rw"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.state_rw.json
}

data "aws_iam_policy_document" "apply" {
  source_policy_documents = [data.aws_iam_policy_document.state_rw.json]

  # Network + load balancing + containers + CDN. These services do not support
  # useful resource-level scoping for create calls; the account-level guard is
  # the permissions boundary + the region/prefix conventions + tag requirements.
  statement {
    sid = "Workload"
    actions = [
      "ec2:*", "elasticloadbalancing:*", "ecs:*", "cloudfront:*",
      "logs:*", "application-autoscaling:*", "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "EcrPushPull"
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:DescribeImages", "ecr:DescribeRepositories", "ecr:ListTagsForResource"]
    resources = [aws_ecr_repository.api.arn]
  }
  statement {
    sid       = "SpaBucket"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::${var.name_prefix}-spa-*", "arn:aws:s3:::${var.name_prefix}-spa-*/*"]
  }
  statement {
    sid       = "SsmRead"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:DescribeParameters", "ssm:ListTagsForResource"]
    resources = ["arn:aws:ssm:*:${local.account_id}:parameter${local.ssm_prefix}/*"]
  }
  statement {
    sid       = "IamOwnRolesOnly"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
    resources = ["arn:aws:iam::${local.account_id}:role/${var.name_prefix}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.boundary_arn]
    }
  }
  statement {
    sid = "IamManageOwnRoles"
    actions = [
      "iam:GetRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateRole",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole", "iam:UpdateAssumeRolePolicy", "iam:PassRole",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/${var.name_prefix}-*"]
  }
  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["ecs.amazonaws.com", "elasticloadbalancing.amazonaws.com"]
    }
  }
  statement {
    sid       = "ReadOnlyEverythingElse"
    actions   = ["iam:Get*", "iam:List*", "sts:GetCallerIdentity", "tag:GetResources"]
    resources = ["*"]
  }
}
resource "aws_iam_role_policy" "apply" {
  name   = "deploy"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}

output "state_bucket" { value = aws_s3_bucket.state.bucket }
output "ecr_repository_url" { value = aws_ecr_repository.api.repository_url }
output "apply_role_arn" { value = aws_iam_role.apply.arn }
output "plan_role_arn" { value = aws_iam_role.plan.arn }
