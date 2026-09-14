data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  public_subnets  = [for k, az in local.azs : cidrsubnet(var.vpc_cidr, var.subnet_newbits, k)]
  private_subnets = [for k, az in local.azs : cidrsubnet(var.vpc_cidr, var.subnet_newbits, k + 10)]

  cart_containers = concat(
    jsondecode(file("${path.module}/task-definitions/cart-service.json")),
    jsondecode(file("${path.module}/task-definitions/cart-db.json"))
  )

  catalog_containers = concat(
    jsondecode(templatefile(
      "${path.module}/task-definitions/catalog-service.json.tftpl",
      {
        db_password = var.db_password
      }
    )),
    jsondecode(templatefile(
      "${path.module}/task-definitions/catalog-db.json.tftpl",
      {
        db_password = var.db_password
      }
    ))
  )

  checkout_containers = concat(
    jsondecode(file("${path.module}/task-definitions/checkout-service.json")),
    jsondecode(file("${path.module}/task-definitions/checkout-db.json"))
  )

  orders_containers = concat(
    jsondecode(templatefile(
      "${path.module}/task-definitions/order-service.json.tftpl",
      {
        db_password = var.db_password
      }
    )),
    jsondecode(templatefile(
      "${path.module}/task-definitions/order-db.json.tftpl",
      {
        db_password = var.db_password
      }
    )),
    jsondecode(templatefile(
      "${path.module}/task-definitions/orders-rabbitmq.json.tftpl",
      {
        db_password = var.db_password
      }
    ))
  )

  ui_containers = jsondecode(
    file("${path.module}/task-definitions/ui-service.json")
  )
}