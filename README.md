# AWS TERRFORM TEST
This project contains everything you need to deploy a dotnet core application on an AWS ECS with terraform, below you can find what features are deployed by terrafom file:
Github Connection
AWS S3
AWS ECR
Network for ECS use
Roles and Policies for ECS use
ECS and dependencies
AWS Roles and Policies for Code Build and Code Pipeline execucion
AWS Code Build Project
AWS Code Pipeline Project

## Pre-requisites
1) If you want run the project locally you must have installed [Docker](https://docs.docker.com/get-docker/) and [Terraform](https://chocolatey.org/packages/terraform) in your local PC.
2) A Github Personal Access Token (PAT)
3) AWS Account (You can use a Free tier account for this test)
4) Create a AWS Access Key

## Usage (Windows Powershell)
To run the project locally in a docker container:
```powershell
cd /aws_test
docker build -t zmg_test_aws:latest .
docker run --name zmg_dck_001 -p 4225:80/tcp zmg_test_aws:latest
```
Go to the URL http://localhost:4225/WeatherForecast

To create all AWS Resources:
Create two enviroments variables in the root Terraform folder
```powershell
cd /aws_test/Terraform
$env:TF_VAR_AWSACCESSKEYID="KEYID"
$env:TF_VAR_AWSSECRETID='KEYSECRET'
```
Then run the following commands:
```powershell
terraform init
terraform plan -out zmgtest
terraform apply zmgtest
```





