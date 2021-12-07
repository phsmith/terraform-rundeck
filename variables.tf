variable "rundeck_url" {
    description = "Rundeck URL"
    type = string
}

variable "rundeck_token" {
    description = "Rundeck Token"
    type = string
    sensitive = true
}

variable "rundeck_api_version" {
    description = "Rundeck API version"
    type = number
    default = 40
}

variable "rundeck_hosts" {
    description = "Rundeck hosts addresses"
    type = string
}

variable "rundeck_hosts_user" {
    description = "Rundeck host username"
    type = string
}

variable "rundeck_hosts_password" {
    description = "Rundeck host user password"
    type = string
    sensitive = true
}

variable "project_name" {
    description = "Project name"
    type = string
    default = ""
}

variable "project_description" {
    description = "Project description"
    type = string
    default = ""
}

variable "job_group_name" {
    description = "Job group name"
    type = string
    default = ""
}

variable "job_name" {
    description = "Job name"
    type = string
    default = ""
}

variable "job_description" {
    description = "Job description"
    type = string
    default = ""
}

variable "job_node_filter_query" {
    description = "Job nodes filter"
    type = string
    default = ""
}

variable "job_log_level" {
    description = "Job log level"
    type = string
    default = "INFO"
}

variable "job_schedule" {
    description = "Schedule job"
    type = string
    default = ""
}

variable "job_allow_concurrent_executions" {
    description = "Allow concurrent job executions"
    type = bool
    default = true
}

variable "job_preserve_options_order" {
    description = "Preserve the job options order"
    type = bool
    default = true
}

variable "job_global_log_filter" {
    description = "Job global log filter expression"
    type = list(object({
        type   = string
        config = object({
            name              = optional(string)
            regex             = string
            logData           = optional(bool)
            hideOutput        = optional(bool)
            invalidKeyPattern = optional(string)
        })
    }))
    default = []
}

variable "job_options" {
    description = "Job options"
    type = list(object({
        name                      = string
        label                     = optional(string)
        description               = optional(string)
        default_value             = optional(string)
        required                  = optional(bool)
        value_choices             = optional(list(string))
        value_choices_url         = optional(string)
        require_predefined_choice = optional(bool)
        validation_regex          = optional(string)
        allow_multiple_values     = optional(bool)
        multi_value_delimiter     = optional(string)
        obscure_input             = optional(bool)
        exposed_to_scripts        = optional(bool)
    }))
    default = []
}

variable "job_workflow_inline_script" {
    description = "Job workflow inline script"
    type = list(string)
    default = []
}

variable "job_workflow_script_file" {
    description = "Job workflow script file"
    type = list(string)
    default = []
}

variable "job_workflow_ansible_inline" {
    description = "Job workflow Ansible inline"
    type = list(object({
        ansible-playbook-inline    = string
        ansible-extra-vars         = optional(string)
        ansible-extra-param        = optional(string)
        ansible-disable-limit      = optional(bool)
        ansible-vault-storage-path = optional(string)
    }))
    default = []
}

variable "job_workflow_ansible_playbook" {
    description = "Job workflow Ansible playbook"
    type = list(object({
        ansible-playbook           = string
        ansible-extra-vars         = optional(string)
        ansible-extra-param        = optional(string)
        ansible-disable-limit      = optional(bool)
        ansible-base-dir-path      = optional(string)
        ansible-vault-storage-path = optional(string)
    }))
    default = []
}

variable "job_notifications_email" {
    type = list(object({
        type       = string
        subject    = string
        recipients = list(string)
        attach_log = bool
    }))
    default = []
}

variable "job_notifications_webhook" {
    type = list(object({
        type         = string
        webhook_urls = list(string)
    }))
    default = []
}

variable "job_notifications_slack" {
    type = list(object({
        type             = string
        webhook_base_url = string
        webhook_token    = string
    }))
    default = []
}

locals {
  job_options = defaults(var.job_options, {
    exposed_to_scripts    = true
    multi_value_delimiter = ","
  })
  job_workflow_ansible_inline = defaults(var.job_workflow_ansible_inline, {
    ansible-disable-limit = true
  })
  job_workflow_ansible_playbook = defaults(var.job_workflow_ansible_playbook, {
    ansible-disable-limit = true
    ansible-base-dir-path = "/projects/$${job.project}"
  })
}
