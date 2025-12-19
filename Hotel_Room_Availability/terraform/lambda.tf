# Archive the Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/hotel-room-availability"
  output_path = "${path.module}/../lambda/hotel-room-availability.zip"
}

# Lambda Function
resource "aws_lambda_function" "hotel_room_availability" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "hotel-room-availability"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.hotel_room_availability.name
    }
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "hotel-room-availability-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda Logging
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM Policy for DynamoDB Access
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "hotel-room-availability-dynamodb-policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.hotel_room_availability.arn
      }
    ]
  })
}


# Upload Schema to S3 (Reusing the KB bucket for convenience)
resource "aws_s3_object" "api_schema" {
  bucket = aws_s3_bucket.kb_bucket.id
  key    = "hotelRoomAvailability_schema.yaml"
  source = "${path.module}/../schema/hotelRoomAvailability_schema.yaml"
  etag   = filemd5("${path.module}/../schema/hotelRoomAvailability_schema.yaml")
}

# Bedrock Agent Action Group
resource "aws_bedrockagent_agent_action_group" "hotel_availability_action_group" {
  agent_id          = aws_bedrockagent_agent.vr_hotel_booking_agent.id
  agent_version     = "DRAFT"
  action_group_name = "hotel-availability-actions"
  description       = "Action group to check hotel room availability"

  action_group_executor {
    lambda = aws_lambda_function.hotel_room_availability.arn
  }

  api_schema {
    s3 {
      bucket_name = aws_s3_bucket.kb_bucket.id
      key         = aws_s3_object.api_schema.key
    }
  }
}

# Permission for Bedrock to invoke Lambda
resource "aws_lambda_permission" "allow_bedrock" {
  statement_id  = "AllowBedrockInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hotel_room_availability.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = "arn:aws:bedrock:us-east-1:${data.aws_caller_identity.current.account_id}:agent/${aws_bedrockagent_agent.vr_hotel_booking_agent.id}"
}
