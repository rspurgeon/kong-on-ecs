variable "aws_region" {
  type = string
  default = "us-west-2"
}
variable "aws_vpc_id" {
	description = "The aws VPC ID"
}
variable "aws_subnet_ids" {
	description = "list of subnet ids"
	type = list(string)
}
