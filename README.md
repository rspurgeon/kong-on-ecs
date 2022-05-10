## usage

Set `AWS_PROFILE`, or configure the aws provider via these options: https://registry.terraform.io/providers/hashicorp/aws/latest/docs

Add a `terraform.tfvars` file with values for the vpc, subnet, etc...

`terraform plan -out plan`

if all looks good

`terraform apply plan`

To create a new service (Httpie)
`http $KONG_GW_IP:8001/services name=example-service url=http://mockbin.org`

To create a new route:
`$KONG_GW_IP:8001/services/example-service/routes "hosts[]=example.com"`
