job_group_name = "Validations"

job_name = "test"

job_description = "Test job"

job_options = [
    {
        name = "name"
        label = "Name"
        description = "User first name"
        required = true
    },
    {
        name = "surname"
        label = "Surname"
    }
]

job_workflow_inline_script = [
    <<-EOF
    echo "Hi there, $RD_OPTION_SURNAME $RD_OPTION_NAME!!!"
    exit 0
    EOF
    ,
    "echo 'Testing runs successfully!!!'"
]

job_workflow_script_file = [
    "/projects/example/scripts/test.sh"
]

job_workflow_ansible_inline = [
    {
        ansible-playbook-inline = <<-EOF
            ---

            - hosts: localhost
              connection: local
              gather_facts: false
              tasks:
              - debug:
                  var: inventory_hostname
        EOF
    }
]

job_workflow_ansible_playbook = [
    {
        ansible-playbook = "./playbooks/playbook.yml"
    }
]


job_notifications_slack = [
    {
        type             = "on_success"
        webhook_base_url = "https://hooks.slack.com/services"
        webhook_token    = "TBxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    },
    {
        type             = "on_failure"
        webhook_base_url = "https://hooks.slack.com/services"
        webhook_token    = "TBxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    }
]

job_global_log_filter = [
     {
        type   = "key-value-data-multilines"
        config = {
            regex      = "^(.+?)\\s*=\\s*(.+)"
            logData    = true
            hideOutput = false
        }
    }
]
