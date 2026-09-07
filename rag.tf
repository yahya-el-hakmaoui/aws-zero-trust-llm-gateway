data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "rag_documents" {
  bucket = "${var.project_name}-rag-documents"

  tags = {
    Name = "${var.project_name}-rag-documents"
  }
}

resource "aws_s3_bucket_public_access_block" "rag_documents" {
  bucket = aws_s3_bucket.rag_documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "rag_documents" {
  bucket = aws_s3_bucket.rag_documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "company_info" {
  bucket = aws_s3_bucket.rag_documents.id
  key    = "company-info.txt"

  source = "${path.module}/documents/company-info.txt"

  etag = filemd5("${path.module}/documents/company-info.txt")
}

resource "aws_s3vectors_vector_bucket" "rag" {
  vector_bucket_name = "${var.project_name}-rag-vectors"
  force_destroy      = true
}

resource "aws_s3vectors_index" "rag" {
  index_name         = "company-info"
  vector_bucket_name = aws_s3vectors_vector_bucket.rag.vector_bucket_name

  data_type       = "float32"
  dimension       = 1024
  distance_metric = "cosine"

  metadata_configuration {
    non_filterable_metadata_keys = [
      "AMAZON_BEDROCK_TEXT",
      "AMAZON_BEDROCK_METADATA"
    ]
  }
}

resource "aws_iam_role" "bedrock_knowledge_base" {
  name = "${var.project_name}-bedrock-kb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "bedrock.amazonaws.com"
        }

        Action = "sts:AssumeRole"

        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }

          ArnLike = {
            "AWS:SourceArn" = "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "bedrock_knowledge_base" {
  name = "${var.project_name}-bedrock-kb-policy"
  role = aws_iam_role.bedrock_knowledge_base.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "S3SourceDocuments"
        Effect = "Allow"

        Action = [
          "s3:ListBucket"
        ]

        Resource = aws_s3_bucket.rag_documents.arn
      },
      {
        Sid    = "S3SourceObjects"
        Effect = "Allow"

        Action = [
          "s3:GetObject"
        ]

        Resource = "${aws_s3_bucket.rag_documents.arn}/*"
      },
      {
        Sid    = "BedrockEmbeddings"
        Effect = "Allow"

        Action = [
          "bedrock:InvokeModel"
        ]

        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
      },
      {
        Sid    = "S3Vectors"
        Effect = "Allow"

        Action = [
          "s3vectors:PutVectors",
          "s3vectors:GetVectors",
          "s3vectors:DeleteVectors",
          "s3vectors:QueryVectors",
          "s3vectors:GetIndex"
        ]

        Resource = aws_s3vectors_index.rag.index_arn
      }
    ]
  })
}

resource "aws_bedrockagent_knowledge_base" "rag" {
  name        = "${var.project_name}-knowledge-base"
  description = "Company information knowledge base"

  role_arn = aws_iam_role.bedrock_knowledge_base.arn

  knowledge_base_configuration {
    type = "VECTOR"

    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }

  storage_configuration {
    type = "S3_VECTORS"

    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.rag.index_arn
    }
  }
}

resource "aws_bedrockagent_data_source" "rag" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.rag.id

  name        = "${var.project_name}-documents"
  description = "Company information documents"

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn = aws_s3_bucket.rag_documents.arn
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"

      fixed_size_chunking_configuration {
        max_tokens         = 512
        overlap_percentage = 20
      }
    }
  }
}

resource "terraform_data" "rag_ingestion" {
  triggers_replace = [
    aws_s3_object.company_info.etag,
    aws_bedrockagent_knowledge_base.rag.id,
    aws_bedrockagent_data_source.rag.data_source_id
  ]

  depends_on = [
    aws_bedrockagent_data_source.rag
  ]

  provisioner "local-exec" {
    command = <<-EOT
      aws bedrock-agent start-ingestion-job \
        --region "${var.aws_region}" \
        --knowledge-base-id "${aws_bedrockagent_knowledge_base.rag.id}" \
        --data-source-id "${aws_bedrockagent_data_source.rag.data_source_id}"
    EOT
  }
}