output "vpc_id" {
  description = "ID of the SRE platform VPC"
  value       = aws_vpc.sre_vpc.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}
output "web_instance_id" {
  description = "ID of the web EC2 instance"
  value       = aws_instance.web.id
}

output "web_public_ip" {
  description = "Public IP address of the web server"
  value       = aws_instance.web.public_ip
}

output "public_subnet_b_id" {
  description = "ID of the second public subnet"
  value       = aws_subnet.public_b.id
}

output "private_subnet_a_id" {
  description = "ID of private subnet A"
  value       = aws_subnet.private_a.id
}

output "private_subnet_b_id" {
  description = "ID of private subnet B"
  value       = aws_subnet.private_b.id
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = aws_route_table.private.id
}

output "web_target_group_arn" {
  description = "ARN of the web application target group"
  value       = aws_lb_target_group.web.arn
}

output "alb_dns_name" {
  description = "DNS name of the application load balancer"
  value       = aws_lb.web.dns_name
}

output "alb_arn" {
  description = "ARN of the application load balancer"
  value       = aws_lb.web.arn
}