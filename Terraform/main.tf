provider "aws" {
  region = "us-east-2"
  access_key = var.AWSACCESSKEYID
  secret_key = var.AWSSECRETID
}

#Get Account info
data "aws_caller_identity" "current" {}

output "user_identity_id" {
  value = data.aws_caller_identity.current.id
}

#Create KMS Key
resource "aws_kms_key" "zmgkmskey" {}

resource "aws_kms_alias" "zmgkmskey" {
  name          = "alias/zmg-kmskey"
  target_key_id = aws_kms_key.zmgkmskey.key_id
}

#Create Github Connection
resource "aws_codestarconnections_connection" "zmg_github" {
  name          = "zmg-connection"
  provider_type = "GitHub"
}

#Create a S3 bucket for Artifacts
resource "aws_s3_bucket" "zmgartifactsstore" {
  bucket = "zmgartifactstore"
  acl = "private"

  tags = {
    Name = "zmgArtifactStore"
    Environment = "Development" 
  }
}

#Create a S3 bucket for Cache
resource "aws_s3_bucket" "zmgbuildcachestore" {
  bucket = "zmgbuildcachestore"
  acl = "private"

  tags = {
    Name = "zmgBuildCacheStore"
    Environment = "Development" 
  }
}

#Create ECR Repository
resource "aws_ecr_repository" "zmg_ecr" {
  name                 = "zmg-ecr"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

#Create Iam Role for Build Project 001
resource "aws_iam_role" "codebuildiamrole" {
  name = "CodeBuildIamRole001"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

#Create Iam Policy for ECR Role
resource "aws_iam_role_policy" "zmg_ecr_role_policy" {
  role = "CodeBuildIamRole001"
  name = "CodeBuildInlinePolicy"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Resource": [
        "*"
      ],
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:*"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
}

#Create Code Build
resource "aws_codebuild_project" "zmgbuildproject" {
  name           = "zmg-build-project"
  description    = "Build Project"
  build_timeout  = "5"
  queued_timeout = "5"

  service_role = aws_iam_role.codebuildiamrole.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_DOCKER_LAYER_CACHE", "LOCAL_SOURCE_CACHE"]
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:3.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.defaultRegion
    }
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.id
    }
    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = "zmg-ecr"
    }
    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
    }
  }

  source {
    type            = "GITHUB"
    location        = var.githubProject
    git_clone_depth = 1
  }

  tags = {
    Name = "zmgBuildProject"
    Environment = "Development" 
  }
}

#Create Code Deploy
resource "aws_codedeploy_app" "zmgcodedeploy" {
  compute_platform = "ECS"
  name             = "zmg-code-deploy"
}

#Create a Code Pipeline
resource "aws_codepipeline" "codepipeline" {
  name     = "zmg-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.zmgartifactsstore.bucket
    type     = "S3"

    encryption_key {
      id   = data.aws_kms_alias.s3kmskey.arn
      type = "KMS"
    }
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.zmg_github.arn
        FullRepositoryId = "sserje06/aws_test"
        BranchName       = "main"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = "zmg-build-project"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CloudFormation"
      input_artifacts = ["build_output"]
      version         = "1"

      configuration = {
        ActionMode     = "REPLACE_ON_FAILURE"
        Capabilities   = "CAPABILITY_AUTO_EXPAND,CAPABILITY_IAM"
        OutputFileName = "CreateStackOutput.json"
        StackName      = "zmg-code-deploy"
        TemplatePath   = "build_output::sam-templated.yaml"
      }
    }
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name = "code-pipeline-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline_policy"
  role = aws_iam_role.codepipeline_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning",
        "s3:PutObject"
      ],
      "Resource": [
        "${aws_s3_bucket.zmgartifactsstore.arn}",
        "${aws_s3_bucket.zmgartifactsstore.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

data "aws_kms_alias" "s3kmskey" {
  name = "alias/zmg-kmskey"

  depends_on = [
    aws_kms_key.zmgkmskey,
    aws_kms_alias.zmgkmskey
  ]
}