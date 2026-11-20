terraform {
  required_version = ">= 1.9.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7.18"
    }
    utils = {
      source  = "cloudposse/utils"
      version = "~> 2.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.3"
    }
  }
}
