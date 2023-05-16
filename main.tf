terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# VPC and subnet setting
resource "aws_vpc" "mrhustlex_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "Custom VPC"
  }
}

resource "aws_subnet" "mrhustlex_public_subnet" {
  vpc_id            = aws_vpc.mrhustlex_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Public Subnet 1a"
  }
}

resource "aws_subnet" "mrhustlex_public_subnet_b" {
  vpc_id            = aws_vpc.mrhustlex_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "Public Subnet 1b"
  }
}

resource "aws_subnet" "mrhustlex_private_subnet" {
  vpc_id            = aws_vpc.mrhustlex_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Private Subnet"
  }
}

# VPC connectivity
resource "aws_internet_gateway" "mrhustlex_igw" {
  vpc_id = aws_vpc.mrhustlex_vpc.id

  tags = {
    Name = "Internet Gateway"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.mrhustlex_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mrhustlex_igw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.mrhustlex_igw.id
  }

  tags = {
    Name = "Public Route Table"
  }
}

resource "aws_route_table_association" "public_1_rt_a" {
  subnet_id      = aws_subnet.mrhustlex_public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_1_rt_b" {
  subnet_id      = aws_subnet.mrhustlex_public_subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

# Application level
resource "aws_security_group" "web_sg" {
  name   = "SG for the bastion host and alb"
  vpc_id = aws_vpc.mrhustlex_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    security_groups = [aws_security_group.lb_sg.id, aws_security_group.bastion_sg.id]
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
    security_groups = [aws_security_group.lb_sg.id, aws_security_group.bastion_sg.id]
  }


  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web_instance" {
  ami           = "ami-0533f2ba8a1995cf9"
  instance_type = "t2.micro"
  key_name      = "MyKeyPair"

  subnet_id                   = aws_subnet.mrhustlex_private_subnet.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  # associate_public_ip_address = true

  # user_data = <<-EOF
  # #!/bin/bash -ex

  # amazon-linux-extras install nginx1 -y
  # echo "<h1>$(curl https://api.kanye.rest/?format=text)</h1>" >  /usr/share/nginx/html/index.html 
  # systemctl enable nginx
  # systemctl start nginx
  # EOF

  tags = {
    "Name" : "mrhustlex instance"
  }
}

# ALB setting up
resource "aws_lb_target_group" "mrhustlex_tg" {
  name        = "mrhustlex-Target-Group"
  port        = 80
  target_type = "instance"
  protocol    = "HTTP"
  vpc_id      = aws_vpc.mrhustlex_vpc.id
}

resource "aws_alb_target_group_attachment" "tg_attachment" {
  target_group_arn = aws_lb_target_group.mrhustlex_tg.arn
  target_id        = aws_instance.web_instance.id
  port             = 80
}

resource "aws_security_group" "lb_sg" {
  name   = "mrhustlex-Loadbalancer-SG"
  vpc_id = aws_vpc.mrhustlex_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_lb" "mrhustlex_alb" {
  name               = "mrhustlex-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = [aws_subnet.mrhustlex_public_subnet.id, aws_subnet.mrhustlex_public_subnet_b.id]
  tags = {
    Environment = "mrhustlex-lb"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.mrhustlex_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.mrhustlex_tg.arn
  }
}

resource "aws_lb_listener_rule" "static" {
  listener_arn = aws_lb_listener.front_end.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mrhustlex_tg.arn

  }

  condition {
    path_pattern {
      values = ["/var/www/html/index.html"]
    }
  }
}

# bastion host
# ec2 in public subnet which allows connection to ssh and egress to another security group
resource "aws_security_group" "bastion_sg" {
  name   = "mrhustlex-bastion-host-SG"
  vpc_id = aws_vpc.mrhustlex_vpc.id

  ingress {
    description = "allow ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_instance" "bastion_instance" {
  ami           = "ami-0533f2ba8a1995cf9"
  instance_type = "t2.micro"
  key_name      = "bastion"

  subnet_id                   = aws_subnet.mrhustlex_public_subnet.id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true

  tags = {
    "Name" : "mrhustlex Bastion Host"
  }
}
# nat in public subnet
resource "aws_eip" "nat_gateway_eip" {
  vpc = true
}

resource "aws_nat_gateway" "natgw" {
  subnet_id = aws_subnet.mrhustlex_public_subnet.id
  allocation_id = aws_eip.nat_gateway_eip.id
  tags = {
  Name = "NAT GW in public subnet"
  }
}

resource "aws_route_table" "private-route-table" {
  depends_on = [ aws_internet_gateway.mrhustlex_igw, aws_nat_gateway.natgw ]
  vpc_id = aws_vpc.mrhustlex_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.natgw.id
  }
  tags = {
    Name = "private-route-table"
  }
}
resource "aws_route_table_association" "private-route-table-association" {
  depends_on = [ aws_route_table.private-route-table ]
  subnet_id      = aws_subnet.mrhustlex_private_subnet.id
  route_table_id = aws_route_table.private-route-table.id
}