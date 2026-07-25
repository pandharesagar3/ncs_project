
resource "aws_lb" "alb" {
  name               = "${var.env_name}-${var.ecs_task_name}-api" # poc5-admin-api   alb-admin-1961366086.ap-southeast-1.elb.amazonaws.com
  internal           = false
  load_balancer_type = "application"
  subnets            = var.subnets_alb #[aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
  security_groups    = var.sg_alb_id   # to be remove extra group
  tags               = var.tags
}


resource "aws_lb_target_group" "target_group_https" {
  name            = "${var.env_name}-tg-${var.ecs_task_name}-https"
  port            = 443
  protocol        = "HTTPS"
  vpc_id          = var.vpc_id
  target_type     = "ip"
  ip_address_type = "ipv4"
  health_check {
    healthy_threshold = 2
    interval          = 30
    protocol          = "HTTPS"
    port              = 443
    path              = "/health_check/"
  }
  tags = var.tags
}

resource "aws_lb_listener" "listner_https" {

  load_balancer_arn = aws_lb.alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group_https.arn
  }
  tags = merge(var.tags, { "Name" : "listner-${var.ecs_task_name}" })
}

output "alb_dns" {
  value = aws_lb.alb.dns_name
}
