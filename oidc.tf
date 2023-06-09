locals {
  github_token_url = "https://token.actions.githubusercontent.com" 
}

resource "aws_iam_openid_connect_provider" "github" {
  url = local.github_token_url

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [data.tls_certificate.github_token.certificates[0].sha1_fingerprint]
}

data "tls_certificate" "github_token" {
  url = local.github_token_url
  verify_chain = true
}

data "aws_ssm_parameter" "admin_role" {
  name = "/sso-roles/Administrator"
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type = "AWS"
      identifiers = [data.aws_ssm_parameter.admin_role.value]
    }
  }

  statement {
    effect = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test = "StringLike"
      variable = "${replace(local.github_token_url, "https://", "")}:sub"
      values = ["repo:hopkinsth/terraform-workshop-aws-april2023:*"]
    }

    condition {
      test = "StringEquals"
      variable = "${replace(local.github_token_url, "https://", "")}:aud"
      values = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "github" {
  name = "${local.app_name}-gha"

  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

resource "aws_iam_role_policy" "github_terraform" {
  name = "tf"
  role = aws_iam_role.github.id

  policy = jsonencode({
    Statement = [
      {
        "Effect" = "Allow"
        "Action" = [
          "ecs:*",
          "ecr:*",
          "ec2:*",
          "iam:*",
          "s3:*",
          "elasticloadbalancing:*",
          "logs:*",
          "ssm:GetParameter",
        ]
        "Resource" = [
          "*",
        ]
      }
    ]
  })
}