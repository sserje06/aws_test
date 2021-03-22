provider "aws" {
  region = "us-east-2"
  access_key = var.AWSACCESSKEYID
  secret_key = var.AWSSECRETID
}

#Create AWS CodeCommit Repository

resource "aws_codecommit_repository" "zmgrepo" {
  repository_name = "zmgrepo"
  description = "Zemoga Test Repo"
  default_branch = "main"

  tags = {
    Name = "zmgrepo"
    Environment = "Development" 
  }
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