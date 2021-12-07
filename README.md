Terraform-Rundeck
=================

The purpose of the project is providing Rundeck as GitOps, managing projects and jobs though Terraform.

This project aims to abstract the Rundeck web user interface adding the possibility for users to create and manage projects and jobs in Rundeck with code, but It's not necessary to know how to code or understand Terraform, users only need to create a project dir and fill a Terraform vars file (tfvars) with the necessary data.

Project Structure
-----------------

```sh
.
|-- azure-pipelines
|   |-- vars
|   |   |-- nprod.yml
|   |   `-- prod.yml
|   `-- azure-pipelines.yml
|-- projects:
|   |-- example
|   |   |-- acls
|   |   |   `-- project_example.aclpolicy
|   |   |-- inventory
|   |   |   |-- ansible
|   |   |   |   `-- hosts
|   |   |   `-- resources.yml
|   |   |-- jobs
|   |   |   |-- test2.tfvars
|   |   |   `-- test.tfvars
|   |   |-- playbooks
|   |   |   `-- playbook.yml
|   |   `-- scripts
|   |       `-- test.sh
|-- main.tf
|-- provider.tf
|-- README.md
`-- variables.tf
```

**azure-pipelines:** Directory with azure-pipelines definitions

**projects:** Home for Rundeck Projects definitions

**main.tf:** Main Terraform file for managing Rundeck resources

**provider.tf:** Terraform Rundeck provider configurations

**variables.tf:** Project variables definitions

To create a new project you can simple copy the `example` project and modify as needed.

The project structure consists of:

 - **project directory:** The name of the directory will be the name of the project in Rundeck
 - **acls:** Rundeck project and jobs access control policy files. The `name` of the file will represents the name of the policy and must have the extension `.aclpolicy`. See more in [Rundeck ACLs Doc](https://docs.rundeck.com/docs/administration/security/authorization.html#access-control-policy-2).
 - **inventory:** Rundeck nodes definitions. The `nodes` in Rundeck represents the target hosts where the jobs will be executed. The inventory can be defined as yaml, xml or json files as specified in the [documentation](https://docs.rundeck.com/docs/administration/projects/resource-model-sources/builtin.html#resource-format-plugins). It can also be defined as Ansible inventory that could be declared in `projects/project_name/inventory/ansible` folder.
 - **jobs:** Here lives the Rundeck Jobs definitions as Terraform tfvars, generally the file name represents the job name, but It is not a rule.
 - **any**: Any other folders or files listed insided the project structure will be copied to the Rundeck host so they could be referenced with the path `/projects/project_name/....`. Example: `/projects/example/playbooks/test.yml`.

Create Jobs
-----------

To create a job you need to define a Terraform `.tfvars` file  in the folder `projects/project_name/jobs`.

Below is a list of possible variables to define in the job .tfvars file.

:warning: At last one `job_workflow_...` option is required.

| Variable | Options | Description |
| --- | --- | --- |
| job_group_name (**required**) | | Job group name for organization.  |
| job_name (**required**) | | Job name. |
| job_description (**optional**) | **Default:** ""| The job description. |
| job_node_filter_query (**optional**) | **Default:** rundeck server| Filter nodes where the jobs will be executed. |
| job_log_level (**optional**) | **Default:** INFO | The job log level verbosity. |
| job_schedule (**optional**) | | Schedule job with Linux Cronjob format. |
| job_allow_concurrent_executions (**optional**) | **Default:** true | Allow concurrent job executions. |
| job_preserve_options_order (**optional**) | **Default:** true | Preserve the job options order. |
| job_global_log_filter (**optional**) | **Default:** [] | Job global log filter expression.<br />Know more about the options in [variables.tf](./variables.tf).<br />See [Rundeck Log Filters Doc](https://docs.rundeck.com/docs/manual/log-filters/).<br />Example: [projects/example/jobs/test.tfvars](projects/example/jobs/test.tfvars) |
| job_options (**optional**) | **Default:** [] | Job input options.<br />Know more about the options in variables.tf.<br />See [Rundeck Job Options Doc](https://docs.rundeck.com/docs/manual/job-options.html#prompting-the-user). |
| job_workflow_inline_script (**optional**) | **Default:** [] | Job workflow where the code is declrared direct within the job definition.<br />Example: [projects/example/jobs/test.tfvars](projects/example/jobs/test.tfvars) |
| job_workflow_script_file (**optional**) | **Default:** [] | Job workflow where the code is defined in a script file.<br />Example: [projects/example/jobs/test.tfvars](projects/example/jobs/test.tfvars)  |
| job_workflow_ansible_inline (**optional**) | **Default:** [] | Job workflow where the Ansible Playbook code is declrared direct within the job definition.<br />Know more about the options in [variables.tf](./variables.tf)<br />Example: [projects/example/jobs/test.tfvars](projects/example/jobs/test.tfvars)  |
| job_workflow_ansible_playbook (**optional**) | **Default:** [] | Job workflow where the Ansible Playbook code is declrared in a YAML file.<br />Know more about the options in [variables.tf](./variables.tf)<br />Example: [projects/example/jobs/test.tfvars](projects/example/jobs/test.tfvars)  |
| job_notifications_email (**optional**) | **Default:** [] | Job notifications configuration using the email type.<br />Know more about the options in [variables.tf](./variables.tf)<br />Example: [projects/example/jobs/test.tfvars](projects/example/jobs/test.tfvars)  |
| job_notifications_webhook (**optional**) | **Default:** [] | Job notifications configuration using the webhooks type.<br />Know more about the options in [variables.tf](./variables.tf)<br />Example: [projects/example/jobs/test.tfvars](projects/example/jobs/test.tfvars)  |
| job_notifications_plugin (**optional**) | **Default:** [] | Job notifications configuration using the plugin type.<br />Know more about the options in [variables.tf](./variables.tf)<br />Example: [projects/example/jobs/test.tfvars](projects/example/jobs/test.tfvars)  |

How the pipeline works
----------------------

To provides the best experience for the users with the minimum knowledge about Terraform, the project uses the [**Terraform Workspaces**](https://www.terraform.io/docs/language/state/workspaces.html) feature, so each job has his own state generated inside his own workspace.

First, there is the **Build Stage**, where Ansible `requirements.yml` file in the projects root is processed with ansible-galaxy command inside the pool, and a artifact is generated.

Next, cames the **Deploy Stage**, that is executed in the **Rundeck environments**, `nprod-rundeck` or `prod-rundeck`, that has the tag `primary` set. First, the artifact with the Ansible roles and collections requirements is extracted in rundeck user home directory in the Rundeck hosts. Then, there are some checks that identifies the .tfvars files for each project and a Terraform Workspace with the project name and job name is selected or created, if not exists. After that the **Terraform Apply** is executed having the project name and the tfvars file as parameters.

![Pipeline FlowChart Light](images/pipeline-flowchart.png#gh-light-mode-only)
![Pipeline FlowChart Dark](images/pipeline-flowchart-white.png#gh-dark-mode-only)

References
----------

- [Rundeck Projects](https://docs.rundeck.com/docs/administration/projects/)
- [Rundeck Jobs](https://docs.rundeck.com/docs/manual/04-jobs.html)
