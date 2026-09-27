variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "dominio" {
  type    = string
  default = "jimmyto09.site"
}

variable "subdominio" {
  type    = string
  default = "app"
}

variable "tipo_instancia" {
  type    = string
  default = "t3.micro"
}

variable "nombre_clave_ec2" {
  type    = string
  default = "ec2_ansible_https"
}

variable "mi_ip_ssh" {
  type    = string
  default = "92.191.100.185/32"
}