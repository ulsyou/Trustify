#region Application Load Balancer
resource "aws_lb" "this" {
  name = "${var.name_prefix}-alb"
  internal = false
  load_balancer_type = "application"
  security_groups = [var.security_group_id]
  subnets = var.public_subnet_ids
  enable_deletion_protection = false

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}
#endregion

#region Target Group
resource "aws_lb_target_group" "this" {
  name = "${var.name_prefix}-tg"
  port = var.container_port
  protocol = "HTTP"
  vpc_id = var.vpc_id
  target_type = "ip"
  deregistration_delay = 10

  health_check {
    enabled = true
    path = var.health_check_path
    port = "traffic-port"
    protocol = "HTTP"
    matcher = "200-299"
    interval = 30
    timeout = 5
    healthy_threshold = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.name_prefix}-tg"
  }
}
#endregion

#region HTTP Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port = 80
  protocol = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = {
    Name = "${var.name_prefix}-http-listener"
  }
}
#endregion

#region HTTPS Listener
resource "aws_lb_listener" "https" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = {
    Name = "${var.name_prefix}-https-listener"
  }
}
#endregion
