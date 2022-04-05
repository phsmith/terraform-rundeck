resource "rundeck_project" "project" {
  count = var.project_name != "" ? 1 : 0

  name                            = var.project_name
  description                     = var.project_description
  default_node_file_copier_plugin = var.project_default_node_file_copier_plugin
  default_node_executor_plugin    = var.project_default_node_executor_plugin

  # ssh_key_storage_path = "${rundeck_private_key.anvils.path}"
  ssh_authentication_type = "password"

  resource_model_source {
    type = "local"

    config = {
      description = "Rundeck server node"
    }
  }

  resource_model_source {
    type = "directory"

    config = {
      directory = "/projects/${var.project_name}/inventory"
    }
  }

  resource_model_source {
    type = "com.batix.rundeck.plugins.AnsibleResourceModelSourceFactory"

    config = {
      ansible-inventory        = "/projects/${var.project_name}/inventory/ansible"
      ansible-config-file-path = "/projects/${var.project_name}"
      ansible-gather-facts     = false
      ansible-ignore-errors    = true
    }
  }

  dynamic "resource_model_source" {
    for_each = var.project_kubernetes_resource_models

    content {
      type   = "kubernetes-resource-model"
      config = resource_model_source.value
    }
  }

  extra_config = var.project_extra_configs
}

data "local_file" "aclpolicies" {
  for_each = var.project_name != "" ? fileset("./projects/${var.project_name}/acls", "*.aclpolicy") : []
  filename = "./projects/${var.project_name}/acls/${each.value}"
}

resource "rundeck_acl_policy" "acl" {
  for_each = data.local_file.aclpolicies

  name   = "${var.project_name}_${basename(each.value.filename)}"
  policy = each.value.content
}

resource "rundeck_job" "job_workflow" {
  count = var.job_name != "" ? 1 : 0

  name                        = var.job_name
  project_name                = var.project_name
  timeout                     = var.job_timeout
  group_name                  = var.job_group_name
  description                 = var.job_description
  log_level                   = var.job_log_level
  node_filter_query           = var.job_node_filter_query
  node_filter_exclude_query   = var.job_node_filter_exclude_query
  schedule_enabled            = var.job_schedule_enabled
  schedule                    = var.job_schedule
  allow_concurrent_executions = var.job_allow_concurrent_executions
  preserve_options_order      = var.job_preserve_options_order
  rank_order                  = var.job_rank_order

  max_thread_count            = var.job_workflow_max_thread_count
  continue_next_node_on_error = var.job_workflow_continue_next_node_on_error
  command_ordering_strategy   = var.job_workflow_strategy
  retry                       = var.job_workflow_retry

  dynamic "option" {
    for_each = local.job_options

    content {
      name                      = option.value.name
      label                     = option.value.label
      description               = option.value.description
      default_value             = option.value.default_value
      required                  = option.value.required
      value_choices             = option.value.value_choices
      value_choices_url         = option.value.value_choices_url
      require_predefined_choice = option.value.require_predefined_choice
      validation_regex          = option.value.validation_regex
      allow_multiple_values     = option.value.allow_multiple_values
      multi_value_delimiter     = option.value.multi_value_delimiter
      obscure_input             = option.value.obscure_input
      exposed_to_scripts        = option.value.exposed_to_scripts
    }
  }

  dynamic "global_log_filter" {
    for_each = var.job_global_log_filter

    content {
      type   = global_log_filter.value.type
      config = global_log_filter.value.config
    }
  }

  dynamic "command" {
    for_each = var.job_workflow_inline_script

    content {
      inline_script = command.value
    }
  }

  dynamic "command" {
    for_each = var.job_workflow_script_file

    content {
      script_file = command.value
    }
  }

  dynamic "command" {
    for_each = local.job_workflow_ansible_inline

    content {
      step_plugin {
        type   = "com.batix.rundeck.plugins.AnsiblePlaybookInlineWorkflowStep"
        config = command.value
      }
    }
  }

  dynamic "command" {
    for_each = local.job_workflow_ansible_playbook

    content {
      step_plugin {
        type   = "com.batix.rundeck.plugins.AnsiblePlaybookWorkflowStep"
        config = command.value
      }
    }
  }

  dynamic "command" {
    for_each = local.job_workflow_node_ansible_inline

    content {
      step_plugin {
        type   = "com.batix.rundeck.plugins.AnsiblePlaybookInlineWorkflowNodeStep"
        config = command.value
      }
    }
  }

  dynamic "command" {
    for_each = local.job_workflow_node_ansible_playbook

    content {
      node_step_plugin {
        type   = "com.batix.rundeck.plugins.AnsiblePlaybookWorflowNodeStep"
        config = command.value
      }
    }
  }

  dynamic "notification" {
    for_each = var.job_notifications_email

    content {
      type = notification.value.type
      email {
        subject    = notification.value.subject
        recipients = notification.value.recipients
        attach_log = notification.value.attach_log
      }
    }
  }

  dynamic "notification" {
    for_each = var.job_notifications_webhook

    content {
      type         = notification.value.type
      webhook_urls = notification.value.webhook_urls
    }
  }

  dynamic "notification" {
    for_each = var.job_notifications_slack

    content {
      type = notification.value.type
      plugin {
        type = "SlackNotification"
        config = {
          webhook_base_url = notification.value.webhook_base_url
          webhook_token    = notification.value.webhook_token
        }
      }
    }
  }
}

resource "null_resource" "copy_project_files" {
  for_each = var.project_name != "" ? toset(split(",", var.rundeck_hosts)) : []

  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "remote-exec" {
    inline = [
      "rm -rf /projects/${var.project_name}/*",
      "rm -rf /var/tmp/terraform_*.sh"
    ]
  }

  provisioner "file" {
    source      = "projects/${var.project_name}"
    destination = "/projects"
  }

  connection {
    host            = each.value
    type            = "ssh"
    agent           = false
    user            = var.rundeck_hosts_user
    password        = var.rundeck_hosts_password
    target_platform = "unix"
    script_path     = "/var/tmp/terraform_%RAND%.sh"
  }
}

resource "null_resource" "load_job_from_yaml" {
  count = var.job_yaml_file != "" ? 1 : 0

  triggers = {
    check_sum     = filemd5(var.job_yaml_file)
    project_name  = var.project_name
    rundeck_url   = var.rundeck_url
    rundeck_token = var.rundeck_token
    file          = var.job_yaml_file
  }

  provisioner "local-exec" {
    command = "rd jobs load --file='${self.triggers.file}' --project='${var.project_name}' --format='yaml' --remove-uuids --verbose"

    environment = {
      RD_URL   = var.rundeck_url
      RD_TOKEN = var.rundeck_token
    }
  }

  provisioner "local-exec" {
    command = "rd jobs purge --file='${self.triggers.file}' --project='${self.triggers.project_name}' --format='yaml' --verbose"

    environment = {
      RD_URL   = self.triggers.rundeck_url
      RD_TOKEN = self.triggers.rundeck_token
    }

    when       = destroy
    on_failure = continue
  }

  lifecycle {
    create_before_destroy = true
  }
}
