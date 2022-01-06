#!/bin/bash

set -e

plan_or_apply=$1

if [[ ! "$plan_or_apply" =~ ^(plan|apply) ]]; then
    echo "Usage: terraform_plan_apply.sh plan or apply"
    exit 1
elif [[ "$plan_or_apply" == "plan" ]]; then
    terraform_default_options="-input=false -compact-warnings -out rundeck.tfplan"
else
    terraform_default_options="-auto-approve -input=false -compact-warnings"
fi

terraform init -upgrade
terraform workspace select default

git_diff=`git diff --name-status HEAD~1..HEAD | sort -u`

echo "$git_diff" \
| grep -Ev "(/jobs/.*.tfvars$|acls/.*.aclpolicy)" \
| awk '/projects/ {print $1"\t"$2"\t"$NF}' \
| sed -r 's@(^[ADRM])[0-9]+?\s+(\bprojects/[a-zA-Z0-9_-]+\b).+(\bprojects/[a-zA-Z0-9_-]+\b).+@\1 \2 \3@g' \
| uniq \
| while read status changed_projects
do
    old_project_name=`awk '{print $1}' <<<$changed_projects | cut -d'/' -f2`
    project_name=`awk '{print $NF}' <<<$changed_projects | cut -d'/' -f2`

    # Migrate terraform state to the new workspace if renames ocurred
    if [[ $status =~ ^R ]]; then
        old_tfstate="/tmp/${old_project_name}.tfstate"
        terraform workspace select $old_project_name 2>/dev/null || continue
        echo -e "- Migrating state from workspace ${old_project_name} to ${project_name}...\n"
        terraform state pull > $old_tfstate
        terraform workspace new $project_name 2> /dev/null || true
        terraform workspace select $project_name || true
        terraform state push $old_tfstate
        rm -f $old_tfstate
    fi

    # Destroy the project if It has been deleted or the dir not exists
    if [[ "$status" == "D" && ! -d "projects/$old_project_name" && $plan_or_apply == "apply" ]]; then
        if [[ "$old_project_name" == "$project_name" ]]; then
            terraform workspace select $old_project_name || true
            echo -e "- Destroying workspace ${old_project_name}...\n"
            terraform destroy $terraform_default_options -var project_name=$old_project_name || true
        fi

        terraform workspace select default
        terraform workspace delete -force $old_project_name || true
        continue
    fi

    # Create the project workspace and apply the project config
    if [[ $status =~ [ARM] && ! -f /tmp/terraform-rundeck-${project_name}.run ]]; then
        touch /tmp/terraform-rundeck-${project_name}.run
        terraform workspace new $project_name 2> /dev/null || true
        terraform workspace select $project_name || true
        terraform_options="
            $terraform_default_options
            -target rundeck_project.project
            -target null_resource.copy_project_files
            -var project_name=$project_name
        "
        terraform $plan_or_apply $terraform_options
    fi
done

rm -f /tmp/terraform-rundeck-*.run 2> /dev/null || true

# Jobs plan or apply
echo "$git_diff" | grep -E "(/jobs/.*.tfvars$|acls/.*.aclpolicy)" \
| while read status changed_file
do
    project_name=`awk -F'/' '{print $2}' <<<$changed_file`

    # Define the job config to be applied
    if [[ "$changed_file" =~ tfvars ]]; then
        old_tfvar_file=`awk '{print $1}' <<<${changed_file}`
        tfvar_file=`awk '{print $NF}' <<<${changed_file}`
        job_name=`sed "s@projects/$project_name/jobs/@@g;s@/@_@g" <<<${tfvar_file%%.tfvars}`
        old_job_name=`sed "s@projects/$project_name/jobs/@@g;s@/@_@g" <<<${old_tfvar_file%%.tfvars}`
        terraform_options="
            $terraform_default_options
            -target rundeck_job.job_workflow
            -var project_name=$project_name
            -var-file ./$tfvar_file
        "
    # Define the acls to be applied
    elif [[ "$changed_file" =~ aclpolicy ]]; then
        job_name="acls"
        old_job_name=$job_name
        terraform_options="
            $terraform_default_options
            -target local_file.aclpolicy
            -target rundeck_acl_policy.acl
            -var project_name=$project_name
        "
    else
        continue
    fi

    # Migrate terraform state to the new workspace if renames ocurred
    if [[ $status =~ ^R ]]; then
        old_tfstate="/tmp/${old_job_name}.tfstate"
        old_workspace="${project_name}_${old_job_name}"
        workspace="${project_name}_${job_name}"
        terraform workspace select $old_workspace 2>/dev/null  || continue
        echo -e "- Migrating state from workspace ${old_workspace} to ${workspace}...\n"
        terraform state pull > $old_tfstate
        terraform workspace new $workspace 2> /dev/null || true
        terraform workspace select $workspace || true
        terraform state push $old_tfstate
        rm -f $old_tfstate
    fi

    # Destroy the job if It has been deleted or renamed on git
    if [[ $status =~ [DR] && $plan_or_apply == "apply" ]]; then
        workspace="${project_name}_${old_job_name}"

        if [[ "$old_job_name" == "$job_name" ]]; then
            terraform workspace select $workspace || true
            echo -e "- Destroying workspace ${old_workspace}...\n"
            terraform destroy $terraform_default_options
        fi

        terraform workspace select default
        terraform workspace delete -force $workspace || true
    fi

    # Create the job workspace and apply the job config
    if [[ $status =~ [ARM] ]]; then
        workspace="${project_name}_${job_name}"
        terraform workspace new $workspace 2> /dev/null || true
        terraform workspace select $workspace
        terraform $plan_or_apply $terraform_options
        # | awk '/Warning/ {exit} {print}'
    fi
done

# Remove no existent project folder from /projects
if [[ "$plan_or_apply" == "apply" ]]; then
    comm -23 \
        <(ls /projects/ | sort -u) \
        <(terraform workspace list | sed -r '/(default|^$)/d;s/(\* |\s+)//' | sort -u) |
    while read project
    do
        sudo su rundeck -c "rm -rf /projects/$project"
    done
fi
