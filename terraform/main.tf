# --- Provider & VPC ---
provider "aws" { region = "us-east-1" }

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "techkraft-vpc" }
}

data "aws_availability_zones" "available" { state = "available" }

# Public Subnets (ALB & NAT Gateway)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
}

# Private Subnets (App & DB)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
}

# NAT Gateway for Private Subnet Updates
resource "aws_eip" "nat" { domain = "vpc" }
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
}

# --- Security Groups ---
resource "aws_security_group" "alb_sg" {
  name = "alb-sg"
  vpc_id = aws_vpc.main.id
  ingress { from_port = 80; to_port = 80; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}

resource "aws_security_group" "app_sg" {
  name = "app-sg"
  vpc_id = aws_vpc.main.id
  ingress { 
    from_port = 80; to_port = 80; protocol = "tcp"; 
    security_groups = [aws_security_group.alb_sg.id] 
  }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}

# --- Load Balancing & Scaling ---
resource "aws_lb" "web" {
  name = "techkraft-alb"
  load_balancer_type = "application"
  subnets = aws_subnet.public[*].id
  security_groups = [aws_security_group.alb_sg.id]
}

resource "aws_autoscaling_group" "web" {
  desired_capacity = 3 [cite: 60]
  max_size = 5
  min_size = 2
  vpc_zone_identifier = aws_subnet.private[*].id
  launch_template { id = aws_launch_template.web.id; version = "$Latest" }
}

# --- RDS Multi-AZ & Encrypted ---
resource "aws_db_subnet_group" "main" {
  name = "db-sn-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "mysql" {
  identifier = "techkraft-db"
  engine = "mysql" [cite: 104]
  instance_class = "db.t3.medium" [cite: 109]
  allocated_storage = 20 [cite: 110]
  multi_az = true
  storage_encrypted = true
  manage_master_user_password = true
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  deletion_protection = true
  backup_retention_period = 7
  skip_final_snapshot = false
}
