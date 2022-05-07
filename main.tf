terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
    }
  }
}

data "aws_iam_policy_document" "ecs_tasks_execution_role" {
  statement {
    actions = [ "sts:AssumeRole" ]

    principals {
      type        = "Service"
      identifiers = [ "ecs-tasks.amazonaws.com" ]
    }
  }
}

resource "aws_iam_role" "ecs_tasks_execution_role" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_execution_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_tasks_execution_role" {
  role       = aws_iam_role.ecs_tasks_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_service_discovery_private_dns_namespace" "example_domain" {
  name = "example.com"
  vpc  = var.aws_vpc_id
}

resource "aws_security_group" "postgres_ingress_everywhere" {
    name = "postgres_ingress_everywhere"
    description = "Allows traffice to 5432 from anywhere"
    vpc_id = var.aws_vpc_id

    ingress {
      from_port        = 5432
      to_port          = 5432
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
    }
    egress {
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
}

resource "aws_security_group" "kong_gw" {
    name = "kong_gw"
    description = "Rules for Kong GW traffic"
    vpc_id = var.aws_vpc_id

    ingress {
      from_port        = 8000 
      to_port          = 8000
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
    }
    ingress {
      from_port        = 8001
      to_port          = 8001
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
    }
    ingress {
      from_port        = 8443
      to_port          = 8443
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
    }
    ingress {
      from_port        = 8444
      to_port          = 8444
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
    }
    egress {
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
}

resource "aws_ecs_cluster" "kong" {
  name = "kong"
}

resource "aws_cloudwatch_log_group" "kong_database" {
  name = "/kong/kong-database"
}

resource "aws_ecs_task_definition" "kong_database" {
  family = "kong-database"
  requires_compatibilities  = ["FARGATE"]
  network_mode              = "awsvpc"
  cpu                       = 512
  memory                    = 1024
  execution_role_arn        = aws_iam_role.ecs_tasks_execution_role.arn
  container_definitions     = jsonencode([
    {
      name      = "pg"
      image     = "postgres:9.6"
      essential = true
      portMappings = [
        {
          containerPort = 5432 
          hostPort      = 5432
        }
      ]
      environment = [
        { name = "POSTGRES_USER",     value = "kong" },
        { name = "POSTGRES_PASSWORD", value = "kong" },
        { name = "POSTGRES_DB",       value = "kong" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group = "${aws_cloudwatch_log_group.kong_database.name}"
          awslogs-region = var.aws_region 
          awslogs-stream-prefix = "ecs"
        }
      } 
    }
  ])
}

resource "aws_service_discovery_service" "kong_database" {
  name = "kong-database"
  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.example_domain.id
    routing_policy = "MULTIVALUE"
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_service" "kong_database" {
  name              = "kong-database"
  cluster           = aws_ecs_cluster.kong.id
  task_definition   = aws_ecs_task_definition.kong_database.arn
  desired_count     = 1
  launch_type       = "FARGATE"

  network_configuration {
    subnets           = var.aws_subnet_ids
    security_groups   = [ aws_security_group.postgres_ingress_everywhere.id ]
    assign_public_ip  = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.kong_database.arn
  }
}

resource "aws_cloudwatch_log_group" "kong_gateway" {
  name = "/kong/kong-gateway"
}

resource "aws_ecs_task_definition" "kong_gateway" {
  family = "kong-gateway"
  requires_compatibilities  = ["FARGATE"]
  network_mode              = "awsvpc"
  cpu                       = 1024
  memory                    = 2048 
  execution_role_arn = aws_iam_role.ecs_tasks_execution_role.arn
      //entrypoint = [] 
      //command    = [ "/bin/bash", "-c", "/docker-entrypoint.sh", "kong", "migrations", "bootstrap;", "/docker-entrypoint.sh", "kong", "docker-start" ]
      //command = ["kong", "migrations", "bootstrap"]
  container_definitions     = jsonencode([
    {
      name       = "kong-gateway"
      image      = "kong:latest"
      essential  = true
      command = ["kong", "docker-start"]
      portMappings = [ 
        {
          containerPort = 8000
          hostPort      = 8000
        },
        {
          containerPort = 8001
          hostPort      = 8001
        },
        {
          containerPort = 8443
          hostPort      = 8443
        },
        {
          containerPort = 8444
          hostPort      = 8444
        }
      ]
      environment  = [
        { name = "KONG_DATABASE",    value = "postgres" },
        { name = "KONG_PG_USER",     value = "kong" },
        { name = "KONG_PG_PASSWORD", value = "kong" },
        { name = "KONG_PG_HOST",     value = "kong-database.example.com" },
        { name = "KONG_PROXY_ACCESS_LOG", value = "/dev/stdout" },
        { name = "KONG_ADMIN_ACCESS_LOG", value = "/dev/stdout" },
        { name = "KONG_PROXY_ERROR_LOG",  value = "/dev/stderr" },
        { name = "KONG_ADMIN_ERROR_LOG",  value = "/dev/stderr" },
        { name = "KONG_ADMIN_LISTEN",     value = "0.0.0.0:8001, 0.0.0.0:8444 ssl" },
        { name = "KONG_CASSANDRA_CONTACT_POINTS", value = "kong-database" }
      ]
      healthcheck = {
        command = [ "CMD", "kong", "health" ]
        interval = 10
        timeout = 10
        retries = 10
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group = "${aws_cloudwatch_log_group.kong_gateway.name}"
          awslogs-region = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      } 
    }
  ])
}

resource "aws_service_discovery_service" "kong_gateway" {
  name = "kong-gateway"
  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.example_domain.id
    routing_policy = "MULTIVALUE"
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}
resource "aws_ecs_service" "kong_gateway" {
  name              = "kong-gateway"
  cluster           = aws_ecs_cluster.kong.id
  task_definition   = aws_ecs_task_definition.kong_gateway.arn
  desired_count     = 1
  launch_type       = "FARGATE"

  network_configuration {
    subnets           = var.aws_subnet_ids
    security_groups   = [ aws_security_group.kong_gw.id ]
    assign_public_ip  = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.kong_gateway.arn
  }

  depends_on = [ aws_ecs_service.kong_database ]
}
