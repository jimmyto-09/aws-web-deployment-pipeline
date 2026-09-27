output "vpc_id" {
  value = aws_vpc.proyecto.id
}

output "ec2_id" {
  value = aws_instance.aplicacion.id
}

output "ec2_ip_publica" {
  value = aws_instance.aplicacion.public_ip
}

output "alb_dns" {
  value = aws_lb.aplicacion.dns_name
}

output "url" {
  value = "https://${aws_route53_record.app.fqdn}"
}
