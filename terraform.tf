terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2"
    }
    argocd = {
      source  = "argoproj-labs/argocd"
      version = ">= 6"
    }
    utils = {
      source  = "cloudposse/utils"
      version = ">= 1"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3"
    }
  }
}
