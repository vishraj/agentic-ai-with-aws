terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # Change region as needed, Bedrock availability varies
}

# IAM Role for Bedrock Agent
resource "aws_iam_role" "bedrock_agent_role" {
  name = "vr-hotel-booking-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:bedrock:us-east-1:${data.aws_caller_identity.current.account_id}:agent/*"
          }
        }
      }
    ]
  })
}

# IAM Policy for Bedrock Agent to invoke models
resource "aws_iam_role_policy" "bedrock_agent_model_policy" {
  name = "vr-hotel-booking-agent-model-policy"
  role = aws_iam_role.bedrock_agent_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "bedrock:InvokeModel"
        Resource = "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-7-sonnet-20250219-v1:0"
      }
    ]
  })
}

# IAM Policy for Bedrock Agent to retrieve from Knowledge Base
resource "aws_iam_role_policy" "bedrock_agent_kb_policy" {
  name = "vr-hotel-booking-agent-kb-policy"
  role = aws_iam_role.bedrock_agent_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "bedrock:Retrieve"
        Resource = aws_bedrockagent_knowledge_base.hotel_kb.arn
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

# Read instructions from file
data "local_file" "agent_instructions" {
  filename = "${path.module}/agent_instructions"
}

# Bedrock Agent
resource "aws_bedrockagent_agent" "vr_hotel_booking_agent" {
  agent_name              = "vr-hotel-booking-agent"
  agent_resource_role_arn = aws_iam_role.bedrock_agent_role.arn
  foundation_model        = "anthropic.claude-3-7-sonnet-20250219-v1:0"
  instruction             = data.local_file.agent_instructions.content

  # Memory configuration
  memory_configuration {
    enabled_memory_types = ["SESSION_SUMMARY"]
    storage_days         = 30
  }
}

# Association between Agent and Knowledge Base
resource "aws_bedrockagent_agent_knowledge_base_association" "agent_kb_association" {
  agent_id          = aws_bedrockagent_agent.vr_hotel_booking_agent.id
  agent_version     = "DRAFT"
  knowledge_base_id = aws_bedrockagent_knowledge_base.hotel_kb.id
  description       = "Association between hotel booking agent and hotel rooms guide KB"

  knowledge_base_state = "ENABLED"
}



