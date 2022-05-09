variable "aws_region" {
  type = string
  default = "us-west-2"
}
variable "aws_vpc_id" {
	description = "The aws VPC ID"
}
variable "aws_private_subnet_id" {
	type = string
}
variable "aws_public_subnet_id" {
	type = string
}
variable "kong_gw_image_tag" {
  type = string
  default = "kong:2.8.1-ubuntu"
}
variable "postgres_image_tag" {
  type = string
  default = "postgres:9.6"
}
