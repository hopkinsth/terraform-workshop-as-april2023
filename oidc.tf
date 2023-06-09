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

data "aws_iam_policy_document" "github_trust" {
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

resource "aws_iam_role_policy" "github_state" {
  name = "tf_state"
  role = aws_iam_role.github.id

  policy = jsonencode({
    Statement = [
      {
        "Effect" = "Allow"
        "Action" = [
          "s3:GetObject",
          "s3:PutObject",
        ]
        "Resource" = [
          "arn:aws:s3:::rv-thopkins-sandbox-tfstate/bursting-mackerel-dev.tfstate",
        ]
      }
    ]
  })
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
        ]
        "Resource" = [
          "*",
        ]
      }
    ]
  })
}