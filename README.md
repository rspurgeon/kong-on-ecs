## usage

Set `AWS_PROFILE`, or configure the aws provider via these options: https://registry.terraform.io/providers/hashicorp/aws/latest/docs

Add a `terraform.tfvars` file with values for the vpc, subnet, etc...

`terraform plan -out plan`

if all looks good

`terraform apply plan`
