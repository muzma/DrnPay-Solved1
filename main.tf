#A -  VPC and Subnet
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "main-vpc"
  }
}

#B - Public Subnet
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}
#C - Private Subnet
resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"

  tags = {
    Name = "private-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-internet-gateway"
  }
}
resource "aws_eip" "nat" {
  depends_on = [aws_internet_gateway.main]
}
#C - NAT Gateway
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id    = aws_subnet.public.id

  tags = {
    Name = "nat-gateway"
  }
}

# D-  Auto Scaling Group with Config

resource "aws_launch_template" "drnpay" {
  name_prefix   = "drnpay-launch-template"
  image_id      = "ami-08f49baa317796afd"  # <-- AMI
  instance_type = "t2.medium" # <-- D.a : Minimum instance type t2.medium

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "drnpay-instance"
    }
  }
}

resource "aws_autoscaling_group" "drnpay" {
  launch_template {
    id      = aws_launch_template.drnpay.id
    version = "$Latest"
  }

  min_size            = 2 # <-- D.a: Minimum 2 instances
  max_size            = 5 # <-- D.a: Max 5 instances
  desired_capacity    = 3
  vpc_zone_identifier = [aws_subnet.private.id] # <-- D.c: instances must be placed on the 1 private subnet created in point C above.

  tag {
    key                 = "Name"
    value               = "drnpay-asg-instance"
    propagate_at_launch = true
  }
}

# E.a: CPU monitoring
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "cpu_high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name        = "CPUUtilization"
  namespace          = "AWS/EC2"
  period             = "60"
  statistic          = "Average"
  threshold          = "45" #D.b: <-- where scaling policy is CPU >= 45%.
  alarm_description  = "This metric monitors ec2 cpu utilization"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.drnpay.name
  }

  alarm_actions = [
    aws_autoscaling_policy.scale_up_policy.arn,
  ]
}

resource "aws_autoscaling_policy" "scale_up_policy" {
  name                   = "scale_up_policy"
  scaling_adjustment      = 1
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.drnpay.name
}

#E: creates CloudWatch monitoring for instance and resource created
# E.b: memory usage
resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "memory_high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name        = "MemoryUtilization"
  namespace          = "AWS/EC2"
  period             = "60"
  statistic          = "Average"
  threshold          = "80"  
  alarm_description  = "This metric monitors ec2 memory utilization"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.drnpay.name
  }
}
# E.c :status check failure
resource "aws_cloudwatch_metric_alarm" "status_check_failed" {
  alarm_name          = "status_check_failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name        = "StatusCheckFailed"
  namespace          = "AWS/EC2"
  period             = "60"
  statistic          = "Maximum"
  threshold          = "0"
  alarm_description  = "This metric monitors EC2 instance status checks"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.drnpay.name
  }
}
# E.d: network usage
resource "aws_cloudwatch_metric_alarm" "network_usage" {
  alarm_name          = "network_usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name        = "NetworkIn"
  namespace          = "AWS/EC2"
  period             = "60"
  statistic          = "Average"
  threshold          = "10000000"  # Adjust as needed
  alarm_description  = "This metric monitors EC2 network usage"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.drnpay.name
  }
}

#F: Terraform backend should be stored on S3 bucket.
provider "aws" {
    region = "ap-southeast-1"
}

terraform {
  backend "s3" {
    bucket = "drnpay-project"
    key = "terraform/state"
    region = "ap-southeast-1"
  }
}