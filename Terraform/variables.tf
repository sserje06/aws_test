variable "AWSACCESSKEYID" {}
variable "AWSSECRETID" {}
variable "githubProject" {
    type = string
    default = "https://github.com/sserje06/aws_test"
}
variable "defaultRegion" {
    type = string
    default = "us-east-2"
}
