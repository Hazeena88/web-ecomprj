# -----------------------
# Provider
# -----------------------
provider "aws" {
  region = "us-east-1"
}

# -----------------------
# Random ID for uniqueness
# -----------------------
resource "random_id" "unique_suffix" {
  byte_length = 8
}

# -----------------------
# VPC and Networking
# -----------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
}

# -----------------------
# Security Group
# -----------------------
resource "aws_security_group" "backend_sg" {
  name        = "backend-sg"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------
# Key Pair
# -----------------------
resource "aws_key_pair" "windows" {
  key_name   = "webprj"
  public_key = file("~/.ssh/id_rsa.pub")
}

# -----------------------
# Launch Template
# -----------------------
resource "aws_launch_template" "backend_lt" {
  name_prefix   = "backend-lt"
  image_id      = "ami-0f88e80871fd81e91"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.windows.key_name

  network_interfaces {
    security_groups             = [aws_security_group.backend_sg.id]
    associate_public_ip_address = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------
# Load Balancer and Target Group
# -----------------------
resource "aws_lb" "alb" {
  name               = "backend-alb-${random_id.unique_suffix.hex}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.backend_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "backend-tg-${random_id.unique_suffix.hex}"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# -----------------------
# Auto Scaling Group
# -----------------------
resource "aws_autoscaling_group" "backend_asg" {
  name_prefix          = "backend-asg-"
  max_size             = 3
  min_size             = 1
  desired_capacity     = 2
  vpc_zone_identifier  = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  target_group_arns    = [aws_lb_target_group.tg.arn]

  launch_template {
    id      = aws_launch_template.backend_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "backend-instance"
    propagate_at_launch = true
  }
}

# ----------------------------
# S3 Bucket for Frontend Hosting
# ----------------------------
resource "aws_s3_bucket" "frontend_bucket" {
  bucket        = "web-bucket-${random_id.unique_suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_website_configuration" "frontend_website" {
  bucket = aws_s3_bucket.frontend_bucket.bucket

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend_bucket_block" {
  bucket = aws_s3_bucket.frontend_bucket.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# ----------------------------
# IAM Roles for CI/CD
# ----------------------------
resource "aws_iam_role" "codebuild_role" {
  name = "codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "codebuild.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_policy" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess"
}

resource "aws_iam_role" "codedeploy_role" {
  name = "codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "codedeploy.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_policy" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

resource "aws_iam_role" "codepipeline_role" {
  name = "codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "codepipeline.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_policy" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipelineFullAccess"
}

# ----------------------------
# CodeDeploy Application
# ----------------------------
resource "aws_codedeploy_app" "backend_app" {
  name             = "backend-app"
  compute_platform = "Server"
}

# ----------------------------
# CodeBuild Project
# ----------------------------
resource "aws_codebuild_project" "backend_build" {
  name          = "backend-build"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 5

  artifacts {
    type = "NO_ARTIFACTS"
  }

  source {
    type            = "GITHUB"
    location        = "https://github.com/hazeena1101/backend-repo"
    buildspec       = "buildspec.yml"
    git_clone_depth = 1
  }

  environment {
    compute_type     = "BUILD_GENERAL1_SMALL"
    image            = "aws/codebuild/standard:5.0"
    type             = "LINUX_CONTAINER"
    privileged_mode  = true
  }
}

# ----------------------------
# Deployment Group Placeholder (Add target group/ASG appropriately)
# ----------------------------
# resource "aws_codedeploy_deployment_group" "backend_deployment_group" {
#   app_name              = aws_codedeploy_app.backend_app.name
#   deployment_group_name = "backend-deployment-group"
#   service_role_arn      = aws_iam_role.codedeploy_role.arn
#   autoscaling_groups    = [aws_autoscaling_group.backend_asg.name]
#   deployment_config_name = "CodeDeployDefault.OneAtATime"
#   load_balancer_info {
#     target_group_info {
#       name = aws_lb_target_group.tg.name
#     }
#   }
# }
