terraform {
  backend "s3" {
    bucket         = "cloudtech-cloud-concierge-dev"
    # dynamodb_table = "cloudlab-terraform-lock-table-dev"
    encrypt        = true
    key            = "dev/cloudlab/terraform.tfstate"
    profile        = "default"
    region         = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
  // version = "5.72.0"
  profile = "default"

  default_tags {
    tags = {
      "Sistema"         = "cloud-concierge"
      "Ambiente"        = "dev"
      "Centro de Custo" = "0000"
      "Conta Contábil"  = "0000"
      "Finalidade"      = "777"
      "Serviço"         = "0000"
      "backup"          = "no"
    }
  }
}

data "aws_region" "current" {}

data "aws_vpcs" "all_vpcs" {}

locals {
  vpc_id = element(data.aws_vpcs.all_vpcs.ids, 0)
  selected_subnets = [
    element([for s in data.aws_subnet.subnet_details : s.id if s.availability_zone == "${data.aws_region.current.name}a"], 0),
    element([for s in data.aws_subnet.subnet_details : s.id if s.availability_zone == "${data.aws_region.current.name}b"], 0),
    element([for s in data.aws_subnet.subnet_details : s.id if s.availability_zone == "${data.aws_region.current.name}c"], 0)
  ]
}

data "aws_subnets" "available_subnets" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

data "aws_subnet" "subnet_details" {
  for_each = toset(data.aws_subnets.available_subnets.ids)
  id       = each.value
}


variable "sistema" {
  description = "Nome do sistema"
  type        = string
  default = "cloud"
}

variable "ambiente" {
  description = "Nome do ambiente"
  type        = string
  default = "dev"
}

variable "service_name" {
  description = "Nome do serviço"
  type        = string
  default = "concierge"
}

variable "sg_ids" {
  description = "Lista de Security Groups"
  type        = list(string)
  default = [ "sg-07d0e007ad1006ba5" ]
}

variable "app_port" {
  description = "Porta da aplicação"
  type        = number
  default = 8080
}

variable "load_balancing_algorithm_type" {
  description = "Porta da aplicação"
  type        = string
  default = "least_outstanding_requests"
}

resource "aws_lb" "load_balancer" {
  name                       = "${var.sistema}-${var.service_name}-alb-${var.ambiente}"
  internal                   = true
  load_balancer_type         = "application"
  security_groups            = var.sg_ids
  subnets                    = local.selected_subnets
  drop_invalid_header_fields = true
  enable_deletion_protection = false
}

resource "aws_lb_target_group" "target_group" {
  name                          = "${var.sistema}-${var.service_name}-tg-${var.ambiente}"
  port                          = var.app_port
  protocol                      = "HTTP"
  vpc_id                        = local.vpc_id
  target_type                   = "ip"
  load_balancing_algorithm_type = var.load_balancing_algorithm_type

  health_check {
    interval            = 60
    path                = "/actuator/health"
    protocol            = "HTTP"
    timeout             = 20
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }

  deregistration_delay = 60
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = var.app_port
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.target_group.arn
    type             = "forward"
  }
}
