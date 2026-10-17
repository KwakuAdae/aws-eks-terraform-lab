variable "image_tag" {
  description = "Image tag in ECR to deploy. Change it to roll out a new version"
  type        = string
  default     = "v1"
}

variable "replicas" {
  description = "Initial replicas (the HPA adjusts this between min and max)"
  type        = number
  default     = 2
}

variable "hpa_min" {
  type    = number
  default = 2
}

variable "hpa_max" {
  type    = number
  default = 6
}

variable "namespace" {
  type    = string
  default = "website"
}
