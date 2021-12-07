#!/bin/bash

set -e

sudo su rundeck -c '
    mkdir -p /var/lib/rundeck/logs/terraform.tfstate.d/rundeck 2> /dev/null;
    chmod 0777 /var/lib/rundeck/logs/terraform.tfstate.d 2> /dev/null
'

terraform init

git_diff=`git diff --name-status HEAD~1..HEAD | sort -u`
terraform_default_options="-auto-approve -input=false -compact-warnings"

echo "$git_diff" | grep -Eo ".*projects/[a-zA-Z0-9_-]+" | uniq | while read status changed_projects
do
    project_name=`awk -F '/' '{print $2}' <<<$changed_projects`

    # Destroy the project if It has been deleted or the dir not exists
    if [[ $status =~ [DR] && ! -d "$changed_projects"  ]]; then
        terraform workspace select $project_name || echo
        terraform destroy $terraform_default_options -var project_name=$project_name || echo
        terraform workspace select default
        terraform workspace delete $project_name || echo
    fi

    # Create the project workspace and apply the project config
    if [[ $status =~ [AM] ]]; then
        terraform workspace new $project_name 2> /dev/null || echo
        terraform workspace select $project_name || echo
        terraform apply $terraform_default_options -target rundeck_project.project -var project_name=$project_name
    fi
done

echo "$git_diff" | grep -E "(/jobs/.*.tfvars|acls/.*.aclpolicy)" | while read status changed_file
do
    project_name=`awk -F'/' '{print $2}' <<<$changed_file`

    # Define the job config to be applied
    if [[ "$changed_file" =~ tfvars ]]; then
        job_name=`basename ${changed_file%%.tfvars}`
        terraform_targets="-target rundeck_job.job_workflow -target null_resource.copy_project_files"
        terraform_options="$terraform_default_options $terraform_targets -var project_name=$project_name -var-file ./$changed_file"
    # Define the acls to be applied
    elif [[ "$changed_file" =~ aclpolicy ]]; then
        job_name="acls"
        terraform_targets="-target local_file.aclpolicy -target rundeck_acl_policy.acl"
        terraform_options="$terraform_default_options $terraform_targets -var project_name=$project_name"
    else
        continue
    fi

    workspace="${project_name}_${job_name}"

    # Destroy the job if It has been deleted or renamed on git
    if [[ $status =~ [DR] ]]; then
        terraform workspace select $workspace || echo
        terraform destroy $terraform_default_options
        terraform workspace select default
        terraform workspace delete $workspace || echo
    fi

    # Create the job workspace and apply the job config
    if [[ $status =~ [AM] ]]; then
        terraform workspace new $workspace 2> /dev/null || echo
        terraform workspace select $workspace
        terraform apply $terraform_options
        # | awk '/Warning/ {exit} {print}'
    fi
done

# Remove no existent project folder from /projects
comm -23 \
<(ls /projects/ | sort -u) \
<(terraform workspace list | sed -r '/(default|^$)/d;s/(\* |\s+)//' | sort -u) |
while read project
do
    sudo su rundeck -c "rm -rf /projects/$project"
done
