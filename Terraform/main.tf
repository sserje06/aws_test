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

#Create ECS with dependencies
resource "aws_ecs_task_definition" "zmg_ecs_tasks" {
  family = "service"
  container_definitions = jsonencode([
    {
      name      = "first"
      image     = "913071338106.dkr.ecr.us-east-2.amazonaws.com/zmg-ecr"
      cpu       = 2
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])

  volume {
    name      = "service-storage"
    host_path = "/ecs/service-storage"
  }

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:ecs.availability-zone in [us-east-1a, us-east-1b]"
  }
}

resource "aws_ecs_cluster" "zmg_ecs_cluser" {
  name = "zmg_ecs_cluser"
  capacity_providers = [ "FARGATE" ]
}

resource "aws_ecs_service" "zmg_ecs_service" {
  name            = "zmg_ecs"
  cluster         = aws_ecs_cluster.zmg_ecs_cluser.id
  task_definition = aws_ecs_task_definition.zmg_ecs_tasks.arn
  desired_count   = 1

  ordered_placement_strategy {
    type  = "binpack"
    field = "cpu"
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

#Create Iam Policy for Build
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
        "codestar-connections:UseConnection",
        "codestar-connections:GetConnection"
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

#Create Code Pipeline Policies
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
  "Statement": [
      {
          "Action": [
              "iam:PassRole"
          ],
          "Resource": "*",
          "Effect": "Allow",
          "Condition": {
              "StringEqualsIfExists": {
                  "iam:PassedToService": [
                      "cloudformation.amazonaws.com",
                      "elasticbeanstalk.amazonaws.com",
                      "ec2.amazonaws.com",
                      "ecs-tasks.amazonaws.com"
                  ]
              }
          }
      },
      {
          "Action": [
              "codecommit:CancelUploadArchive",
              "codecommit:GetBranch",
              "codecommit:GetCommit",
              "codecommit:GetRepository",
              "codecommit:GetUploadArchiveStatus",
              "codecommit:UploadArchive"
          ],
          "Resource": "*",
          "Effect": "Allow"
      },
      {
          "Action": [
              "codedeploy:CreateDeployment",
              "codedeploy:GetApplication",
              "codedeploy:GetApplicationRevision",
              "codedeploy:GetDeployment",
              "codedeploy:GetDeploymentConfig",
              "codedeploy:RegisterApplicationRevision"
          ],
          "Resource": "*",
          "Effect": "Allow"
      },
      {
          "Action": [
              "codestar-connections:UseConnection"
          ],
          "Resource": "*",
          "Effect": "Allow"
      },
      {
          "Action": [
              "elasticbeanstalk:*",
              "ec2:*",
              "elasticloadbalancing:*",
              "autoscaling:*",
              "cloudwatch:*",
              "s3:*",
              "sns:*",
              "cloudformation:*",
              "rds:*",
              "sqs:*",
              "ecs:*"
          ],
          "Resource": "*",
          "Effect": "Allow"
      },
      {
          "Action": [
              "lambda:InvokeFunction",
              "lambda:ListFunctions"
          ],
          "Resource": "*",
          "Effect": "Allow"
      },
      {
          "Action": [
              "opsworks:CreateDeployment",
              "opsworks:DescribeApps",
              "opsworks:DescribeCommands",
              "opsworks:DescribeDeployments",
              "opsworks:DescribeInstances",
              "opsworks:DescribeStacks",
              "opsworks:UpdateApp",
              "opsworks:UpdateStack"
          ],
          "Resource": "*",
          "Effect": "Allow"
      },
      {
          "Action": [
              "cloudformation:CreateStack",
              "cloudformation:DeleteStack",
              "cloudformation:DescribeStacks",
              "cloudformation:UpdateStack",
              "cloudformation:CreateChangeSet",
              "cloudformation:DeleteChangeSet",
              "cloudformation:DescribeChangeSet",
              "cloudformation:ExecuteChangeSet",
              "cloudformation:SetStackPolicy",
              "cloudformation:ValidateTemplate"
          ],
          "Resource": "*",
          "Effect": "Allow"
      },
      {
          "Action": [
              "codebuild:BatchGetBuilds",
              "codebuild:StartBuild",
              "codebuild:BatchGetBuildBatches",
              "codebuild:StartBuildBatch"
          ],
          "Resource": "*",
          "Effect": "Allow"
      },
      {
          "Effect": "Allow",
          "Action": [
              "devicefarm:ListProjects",
              "devicefarm:ListDevicePools",
              "devicefarm:GetRun",
              "devicefarm:GetUpload",
              "devicefarm:CreateUpload",
              "devicefarm:ScheduleRun"
          ],
          "Resource": "*"
      },
      {
          "Effect": "Allow",
          "Action": [
              "servicecatalog:ListProvisioningArtifacts",
              "servicecatalog:CreateProvisioningArtifact",
              "servicecatalog:DescribeProvisioningArtifact",
              "servicecatalog:DeleteProvisioningArtifact",
              "servicecatalog:UpdateProduct"
          ],
          "Resource": "*"
      },
      {
          "Effect": "Allow",
          "Action": [
              "cloudformation:ValidateTemplate"
          ],
          "Resource": "*"
      },
      {
          "Effect": "Allow",
          "Action": [
              "ecr:DescribeImages"
          ],
          "Resource": "*"
      },
      {
          "Effect": "Allow",
          "Action": [
              "states:DescribeExecution",
              "states:DescribeStateMachine",
              "states:StartExecution"
          ],
          "Resource": "*"
      },
      {
          "Effect": "Allow",
          "Action": [
              "appconfig:StartDeployment",
              "appconfig:StopDeployment",
              "appconfig:GetDeployment"
          ],
          "Resource": "*"
      }
  ],
  "Version": "2012-10-17"
}
EOF

depends_on = [
  aws_iam_role.codepipeline_role
]
}

#Create a Code Pipeline
resource "aws_codepipeline" "codepipeline" {
  name     = "zmg-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.zmgartifactsstore.bucket
    type     = "S3"
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
        OutputArtifactFormat: "CODEBUILD_CLONE_REF"
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
      provider        = "ECS"
      input_artifacts = ["build_output"]
      version         = "1"

      configuration = {
        ClusterName = "zmg_ecs_cluser"
        ServiceName = "zmg_ecs"
      }
    }
  }
}