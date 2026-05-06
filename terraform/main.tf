# --- VPC & Networking ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true [cite: 45]
  enable_dns_support   = true [cite: 46]
}

data "aws_availability_zones" "available" { state = "available" }

# Public Subnets (For ALB & NAT Gateway)
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
}

# Private Subnets (For App & DB)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
}

# NAT Gateway (Ensures Private Instances can pull updates/images)
resource "aws_eip" "nat" { domain = "vpc" }
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
}

# --- Security Groups (The "Security Fix") ---
resource "aws_security_group" "alb_sg" {
  name = "alb-sg"
  vpc_id = aws_vpc.main.id
  ingress { from_port = 80; to_port = 80; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"]; }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"]; }
}

resource "aws_security_group" "app_sg" {
  name = "app-sg"
  vpc_id = aws_vpc.main.id
  ingress { 
    from_port = 80; to_port = 80; protocol = "tcp"; 
    security_groups = [aws_security_group.alb_sg.id] # Only ALB can reach App
  }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"]; }
}

# --- RDS with Encryption & Subnet Groups ---
resource "aws_db_subnet_group" "main" {
  name       = "techkraft-db-sn-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "mysql" {
  identifier              = "techkraft-db"
  engine                  = "mysql" [cite: 104]
  instance_class          = "db.t3.medium" [cite: 109]
  allocated_storage       = 20 [cite: 110]
  db_subnet_group_name    = aws_db_subnet_group.main.name
  multi_az                = true
  storage_encrypted       = true # Compliance Fix
  manage_master_user_password = true
  vpc_security_group_ids  = [aws_security_group.app_sg.id] # Only App can reach DB
  deletion_protection     = true [cite: 116]
  skip_final_snapshot     = false [cite: 115]
}
