# --- Provider & Network Setup ---
provider "aws" { region = "us-east-1" }

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "techkraft-vpc" }
}

data "aws_availability_zones" "available" { state = "available" }

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
}

# NAT Gateway for Private Subnet Internet Access
resource "aws_eip" "nat" { domain = "vpc" }
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
}

# --- Security Groups (Least Privilege) ---
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = aws_vpc.main.id
  ingress { from_port = 80; to_port = 80; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}

resource "aws_security_group" "app_sg" {
  name   = "app-sg"
  vpc_id = aws_vpc.main.id
  ingress { 
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] 
  }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}

# --- Compute & Load Balancing ---
resource "aws_lb" "web" {
  name               = "techkraft-alb"
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb_sg.id]
}

resource "aws_launch_template" "web" {
  name_prefix   = "techkraft-web-"
  image_id      = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.medium"
  network_interfaces { security_groups = [aws_security_group.app_sg.id] }
}

resource "aws_autoscaling_group" "web" {
  desired_capacity    = 3
  max_size            = 5
  min_size            = 2
  vpc_zone_identifier = aws_subnet.private[*].id
  launch_template { id = aws_launch_template.web.id; version = "$Latest" }
}

# --- RDS Database (Multi-AZ & Encrypted) ---
resource "aws_db_subnet_group" "main" {
  name       = "techkraft-db-sn-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "mysql" {
  identifier              = "techkraft-db"
  engine                  = "mysql"
  instance_class          = "db.t3.medium"
  allocated_storage       = 20
  db_subnet_group_name    = aws_db_subnet_group.main.name
  multi_az                = true
  storage_encrypted       = true
  manage_master_user_password = true # AWS Secrets Manager
  vpc_security_group_ids  = [aws_security_group.app_sg.id]
  deletion_protection     = true
  backup_retention_period = 7
  skip_final_snapshot     = false
}
