resource "aws_ecr_repository" "website" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "IMMUTABLE" # v1 always means the same image
  force_delete         = true        # lets `terraform destroy` remove it even with images inside

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "website" {
  repository = aws_ecr_repository.website.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 10 most recent images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}
