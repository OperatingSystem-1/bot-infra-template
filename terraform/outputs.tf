output "redis_instance_id" {
  description = "Redis EC2 instance ID"
  value       = aws_instance.redis.id
}

output "redis_private_ip" {
  description = "Redis private IP (for agent connection)"
  value       = aws_instance.redis.private_ip
}

output "agent_instance_ids" {
  description = "Agent EC2 instance IDs"
  value       = aws_instance.agent[*].id
}

output "agent_public_ips" {
  description = "Agent public IPs (for SSH access)"
  value       = aws_instance.agent[*].public_ip
}

output "agent_private_ips" {
  description = "Agent private IPs"
  value       = aws_instance.agent[*].private_ip
}

output "security_group_id" {
  description = "Security group ID for the agent group"
  value       = aws_security_group.agents.id
}

output "group_manifest" {
  description = "Full group manifest"
  value = {
    group_name = var.group_name
    redis = {
      instance_id = aws_instance.redis.id
      private_ip  = aws_instance.redis.private_ip
    }
    agents = [
      for i, agent in aws_instance.agent : {
        name        = var.agent_names[i]
        instance_id = agent.id
        public_ip   = agent.public_ip
        private_ip  = agent.private_ip
      }
    ]
  }
}
