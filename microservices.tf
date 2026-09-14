resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow trafic for alb"
  vpc_id      = aws_vpc.main.id
  tags        = merge(var.tags, { Name = "${var.environment_name}-alb-sg" })
}

# Service SG
resource "aws_security_group" "service" {
  name        = "service-sg"
  description = "Security group for ECS services"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.environment_name}-service-sg"
  })
}

# Internet -> ALB :80
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
}

# ALB -> Service A :8080
resource "aws_vpc_security_group_ingress_rule" "services_from_alb" {
  security_group_id            = aws_security_group.service.id
  referenced_security_group_id = aws_security_group.alb_sg.id

  from_port   = var.service_ingress_port
  to_port     = var.service_ingress_port
  ip_protocol = "tcp"
}

# EFS security group
resource "aws_security_group" "efs_sg" {
  name        = "efs-sg"
  description = "Allow NFS traffic from ECS services"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.environment_name}-efs-sg"
  })
}

# EFS SG ingress rule
resource "aws_vpc_security_group_ingress_rule" "efs_from_services" {
  security_group_id            = aws_security_group.efs_sg.id
  referenced_security_group_id = aws_security_group.service.id

  from_port   = 2049
  to_port     = 2049
  ip_protocol = "tcp"
}

# Service Connect Service Ingress rule
resource "aws_vpc_security_group_ingress_rule" "services_internal" {
  security_group_id            = aws_security_group.service.id
  referenced_security_group_id = aws_security_group.service.id

  from_port   = 8080
  to_port     = 8080
  ip_protocol = "tcp"
}

# Service egress
resource "aws_vpc_security_group_egress_rule" "service_outbound" {
  security_group_id = aws_security_group.service.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Service ALB egress
resource "aws_vpc_security_group_egress_rule" "alb_outbound" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Application load balancer
resource "aws_lb" "alb" {
  name               = "alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [aws_security_group.alb_sg.id]
  subnets         = [for subnet in aws_subnet.public_subnets : subnet.id]

  tags = merge(var.tags, { Name = "${var.environment_name}-alb" })
}

# Elastic file system
resource "aws_efs_file_system" "efs" {
  creation_token = "${var.environment_name}-efs"

  tags = merge(var.tags, { Name = "${var.environment_name}-efs" })
}

# EFS mount targets
resource "aws_efs_mount_target" "efs-mt" {
  for_each = aws_subnet.private_subnets

  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = each.value.id
  security_groups = [aws_security_group.efs_sg.id]
}

# Task definitions
# Cart task definition
resource "aws_ecs_task_definition" "cart-ecs-td" {
  family                = "cart-service"
  container_definitions = jsonencode(local.cart_containers)

  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  cpu    = "512"
  memory = "1024"



  volume {
    name = "cart-service-storage"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.efs.id
      transit_encryption = "ENABLED"
    }
  }
}

# Catalog task definition
resource "aws_ecs_task_definition" "catalog-ecs-td" {
  family                = "catalog-service"
  container_definitions = jsonencode(local.catalog_containers)

  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  cpu    = "512"
  memory = "1024"

  volume {
    name = "catalog-service-storage"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.efs.id
      transit_encryption = "ENABLED"
    }
  }
}

# Checkout task definition
resource "aws_ecs_task_definition" "checkout-ecs-td" {
  family                = "checkout-service"
  container_definitions = jsonencode(local.checkout_containers)

  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  cpu    = "512"
  memory = "1024"

  volume {
    name = "checkout-service-storage"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.efs.id
      transit_encryption = "ENABLED"
    }
  }
}

# Order task definition
resource "aws_ecs_task_definition" "order-ecs-td" {
  family                = "order-service"
  container_definitions = jsonencode(local.orders_containers)

  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  cpu    = "512"
  memory = "1024"

  volume {
    name = "order-service-storage"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.efs.id
      transit_encryption = "ENABLED"
    }
  }
}

# UI task definition
resource "aws_ecs_task_definition" "ui-ecs-td" {
  family                = "ui-service"
  container_definitions = jsonencode(local.ui_containers)

  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  cpu    = "512"
  memory = "1024"

}

# ECS cluster
resource "aws_ecs_cluster" "cluster" {
  name = "cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Service Discovery
resource "aws_service_discovery_http_namespace" "main" {
  name = "main"
}

# ui target group
resource "aws_lb_target_group" "ui" {
  name        = "ui-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/actuator/health"
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ui.arn
  }
}

# ECS services
# ECS Cart Service
resource "aws_ecs_service" "cart" {
  name            = "cart"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.cart-ecs-td.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn

    service {
      port_name      = "cart"
      discovery_name = "cart"

      client_alias {
        dns_name = "cart"
        port     = 8080
      }
    }
  }

  network_configuration {
    subnets = [
      for subnet in aws_subnet.private_subnets :
      subnet.id
    ]

    security_groups = [
      aws_security_group.service.id
    ]

    assign_public_ip = false
  }
}


# ECS Catalog Service
resource "aws_ecs_service" "catalog" {
  name            = "catalog"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.catalog-ecs-td.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn

    service {
      port_name      = "catalog"
      discovery_name = "catalog"

      client_alias {
        dns_name = "catalog"
        port     = 8080
      }
    }
  }

  network_configuration {
    subnets = [
      for subnet in aws_subnet.private_subnets :
      subnet.id
    ]

    security_groups = [
      aws_security_group.service.id
    ]

    assign_public_ip = false
  }
}


# ECS Checkout Service
resource "aws_ecs_service" "checkout" {
  name            = "checkout"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.checkout-ecs-td.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn

    service {
      port_name      = "checkout"
      discovery_name = "checkout"

      client_alias {
        dns_name = "checkout"
        port     = 8080
      }
    }
  }

  network_configuration {
    subnets = [
      for subnet in aws_subnet.private_subnets :
      subnet.id
    ]

    security_groups = [
      aws_security_group.service.id
    ]

    assign_public_ip = false
  }
}


# ECS Orders Service
resource "aws_ecs_service" "orders" {
  name            = "orders"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.order-ecs-td.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn

    service {
      port_name      = "orders"
      discovery_name = "orders"

      client_alias {
        dns_name = "orders"
        port     = 8080
      }
    }
  }

  network_configuration {
    subnets = [
      for subnet in aws_subnet.private_subnets :
      subnet.id
    ]

    security_groups = [
      aws_security_group.service.id
    ]

    assign_public_ip = false
  }
}

# ECS UI Service
resource "aws_ecs_service" "ui" {
  name            = "ui"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.ui-ecs-td.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn

    service {
      port_name      = "ui"
      discovery_name = "ui"

      client_alias {
        dns_name = "ui"
        port     = 8080
      }
    }
  }

  depends_on = [
    aws_lb_listener.http
  ]

  network_configuration {
    subnets = [
      for subnet in aws_subnet.private_subnets :
      subnet.id
    ]

    security_groups = [
      aws_security_group.service.id
    ]

    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ui.arn
    container_name   = "ui"
    container_port   = 8080
  }
}

