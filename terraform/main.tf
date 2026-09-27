terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "disponibles" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_route53_zone" "dominio" {
  name         = "${var.dominio}."
  private_zone = false
}

# 1. Red: una VPC y dos subredes públicas en distintas zonas.
resource "aws_vpc" "proyecto" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "ansible-proyecto-vpc" }
}

resource "aws_subnet" "publica_a" {
  vpc_id                  = aws_vpc.proyecto.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.disponibles.names[0]
  map_public_ip_on_launch = true
  tags = { Name = "ansible-proyecto-publica-a" }
}

resource "aws_subnet" "publica_b" {
  vpc_id                  = aws_vpc.proyecto.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = data.aws_availability_zones.disponibles.names[1]
  map_public_ip_on_launch = true
  tags = { Name = "ansible-proyecto-publica-b" }
}

resource "aws_internet_gateway" "proyecto" {
  vpc_id = aws_vpc.proyecto.id
  tags = { Name = "ansible-proyecto-igw" }
}

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.proyecto.id
  tags = { Name = "ansible-proyecto-publica" }
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.publica.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.proyecto.id
}

resource "aws_route_table_association" "publica_a" {
  subnet_id      = aws_subnet.publica_a.id
  route_table_id = aws_route_table.publica.id
}

resource "aws_route_table_association" "publica_b" {
  subnet_id      = aws_subnet.publica_b.id
  route_table_id = aws_route_table.publica.id
}

# 2. Tráfico: HTTPS desde Internet al ALB, HTTP desde el ALB a EC2,
# y SSH desde tu IP pública al servidor.
resource "aws_security_group" "alb" {
  name_prefix = "ansible-proyecto-alb-"
  vpc_id      = aws_vpc.proyecto.id
  tags = { Name = "ansible-proyecto-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_salida" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "ec2" {
  name_prefix = "ansible-proyecto-ec2-"
  vpc_id      = aws_vpc.proyecto.id
  tags = { Name = "ansible-proyecto-ec2" }
}

resource "aws_vpc_security_group_ingress_rule" "http_desde_alb" {
  security_group_id            = aws_security_group.ec2.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = var.mi_ip_ssh
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "ec2_salida" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# 3. Servidor con Ubuntu y la clave EC2 ya creada en la consola.
resource "aws_instance" "aplicacion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.tipo_instancia
  key_name                    = var.nombre_clave_ec2
  subnet_id                   = aws_subnet.publica_a.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  root_block_device {
    volume_size = 12
    volume_type = "gp3"
  }
  tags       = { Name = "ansible-proyecto-app" }
  depends_on = [aws_route_table_association.publica_a]
  lifecycle {
    ignore_changes = [ami]
  }
}

# 4. ALB y target group: la EC2 recibe HTTP desde el balanceador.
resource "aws_lb" "aplicacion" {
  name               = "ansible-proyecto-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.publica_a.id, aws_subnet.publica_b.id]
  depends_on         = [aws_route_table_association.publica_a, aws_route_table_association.publica_b]
  tags = { Name = "ansible-proyecto-alb" }
}

resource "aws_lb_target_group" "aplicacion" {
  name     = "ansible-proyecto-app"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.proyecto.id
  health_check {
    path    = "/"
    matcher = "200"
  }
}

resource "aws_lb_target_group_attachment" "ec2" {
  target_group_arn = aws_lb_target_group.aplicacion.arn
  target_id        = aws_instance.aplicacion.id
  port             = 80
}

# 5. ACM pide validar el subdominio mediante DNS en Route 53.
resource "aws_acm_certificate" "aplicacion" {
  domain_name       = "${var.subdominio}.${var.dominio}"
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}

resource "aws_route53_record" "validacion" {
  for_each = {
    for opcion in aws_acm_certificate.aplicacion.domain_validation_options : opcion.domain_name => {
      name   = opcion.resource_record_name
      record = opcion.resource_record_value
      type   = opcion.resource_record_type
    }
  }
  zone_id         = data.aws_route53_zone.dominio.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "aplicacion" {
  certificate_arn         = aws_acm_certificate.aplicacion.arn
  validation_record_fqdns = [for registro in aws_route53_record.validacion : registro.fqdn]
}

# 6. El ALB escucha HTTPS y reenvía al target group.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.aplicacion.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate_validation.aplicacion.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aplicacion.arn
  }
}

# 7. El navegador encuentra el ALB usando app.jimmyto09.site.
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.dominio.zone_id
  name    = "${var.subdominio}.${var.dominio}"
  type    = "A"
  alias {
    name                   = aws_lb.aplicacion.dns_name
    zone_id                = aws_lb.aplicacion.zone_id
    evaluate_target_health = false
  }
}
