# S3 Bucket for Knowledge Base Data
resource "aws_s3_bucket" "kb_bucket" {
  bucket = "vr-hotel-room-information"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kb_bucket_sse" {
  bucket = aws_s3_bucket.kb_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "kb_bucket_versioning" {
  bucket = aws_s3_bucket.kb_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "taj_aguada_pdf" {
  bucket = aws_s3_bucket.kb_bucket.id
  key    = "Taj-Fort-Aguada-Resort&Spa-Goa.pdf"
  source = "${path.module}/../rag/Taj-Fort-Aguada-Resort&Spa-Goa.pdf"
  etag   = filemd5("${path.module}/../rag/Taj-Fort-Aguada-Resort&Spa-Goa.pdf")
}

# OpenSearch Serverless Collection
resource "aws_opensearchserverless_collection" "kb_collection" {
  name        = "hotel-kb-collection"
  type        = "VECTORSEARCH"
  description = "Collection for hotel knowledge base"
}

# Encryption Policy
resource "aws_opensearchserverless_security_policy" "kb_encryption_policy" {
  name = "hotel-kb-encryption"
  type = "encryption"
  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource = [
          "collection/${aws_opensearchserverless_collection.kb_collection.name}"
        ]
      }
    ],
    AWSOwnedKey = true
  })
}

# Network Policy
resource "aws_opensearchserverless_security_policy" "kb_network_policy" {
  name = "hotel-kb-network"
  type = "network"
  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource = [
            "collection/${aws_opensearchserverless_collection.kb_collection.name}"
          ]
        },
        {
          ResourceType = "dashboard"
          Resource = [
            "collection/${aws_opensearchserverless_collection.kb_collection.name}"
          ]
        }
      ]
      AllowFromPublic = true
    }
  ])
}

# Data Access Policy
resource "aws_opensearchserverless_access_policy" "kb_access_policy" {
  name = "hotel-kb-access"
  type = "data"
  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource = [
            "collection/${aws_opensearchserverless_collection.kb_collection.name}"
          ]
          Permission = [
            "aoss:CreateCollectionItems",
            "aoss:DeleteCollectionItems",
            "aoss:UpdateCollectionItems",
            "aoss:DescribeCollectionItems"
          ]
        },
        {
          ResourceType = "index"
          Resource = [
            "index/${aws_opensearchserverless_collection.kb_collection.name}/*"
          ]
          Permission = [
            "aoss:CreateIndex",
            "aoss:DeleteIndex",
            "aoss:UpdateIndex",
            "aoss:DescribeIndex",
            "aoss:ReadDocument",
            "aoss:WriteDocument"
          ]
        }
      ],
      Principal = [
        aws_iam_role.bedrock_kb_role.arn,
        data.aws_caller_identity.current.arn
      ]
    }
  ])
}

# IAM Role for Bedrock Knowledge Base
resource "aws_iam_role" "bedrock_kb_role" {
  name = "bedrock-hotel-kb-role"

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
            "aws:SourceArn" = "arn:aws:bedrock:us-east-1:${data.aws_caller_identity.current.account_id}:knowledge-base/*"
          }
        }
      }
    ]
  })
}

# Policy for Bedrock to access S3
resource "aws_iam_role_policy" "kb_s3_policy" {
  name = "bedrock-kb-s3-policy"
  role = aws_iam_role.bedrock_kb_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.kb_bucket.arn,
          "${aws_s3_bucket.kb_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Policy for Bedrock to access OpenSearch
resource "aws_iam_role_policy" "kb_aoss_policy" {
  name = "bedrock-kb-aoss-policy"
  role = aws_iam_role.bedrock_kb_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aoss:APIAccessAll"
        ]
        Resource = [
          aws_opensearchserverless_collection.kb_collection.arn
        ]
      }
    ]
  })
}


# Bedrock Knowledge Base
resource "aws_bedrockagent_knowledge_base" "hotel_kb" {
  name     = "kb-hotel-rooms-guide"
  role_arn = aws_iam_role.bedrock_kb_role.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.kb_collection.arn
      vector_index_name = "bedrock-knowledge-base-default-index"
      field_mapping {
        vector_field   = "bedrock-knowledge-base-default-vector"
        text_field     = "bedrock-knowledge-base-default-text"
        metadata_field = "bedrock-knowledge-base-default-metadata"
      }
    }
  }

  depends_on = [
    aws_opensearchserverless_security_policy.kb_encryption_policy,
    aws_opensearchserverless_security_policy.kb_network_policy,
    aws_opensearchserverless_access_policy.kb_access_policy
  ]
}

# Knowledge Base Data Source
resource "aws_bedrockagent_data_source" "hotel_kb_datasource" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.hotel_kb.id
  name              = "hotel-kb-datasource"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.kb_bucket.arn
    }
  }
}
