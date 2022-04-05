terraform {
  backend "local" {
    path          = "/var/lib/rundeck/logs/terraform.tfstate.d/rundeck/terraform.tfstate"
    workspace_dir = "/var/lib/rundeck/logs/terraform.tfstate.d/rundeck"
  }
  required_providers {
    rundeck = {
      source  = "rundeck/rundeck"
      version = "0.4.3"
    }
  }
  experiments = [module_variable_optional_attrs]
}

provider "rundeck" {
  url         = var.rundeck_url
  auth_token  = var.rundeck_token
  api_version = var.rundeck_api_version
}
