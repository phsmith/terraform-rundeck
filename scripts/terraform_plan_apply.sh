#!/bin/bash

set -e

# Script arguments
plan_or_apply=$1
environment=$2

export TF_VAR_job_environment=$environment

# Validating if the first arguments passed was plan or apply
if [[ ! "$plan_or_apply" =~ ^(plan|apply|re-apply) ]]; then
    echo "Usage: terraform_plan_apply.sh plan or apply or re-apply [environment]"
    echo ""
    echo "environment: prod or staging"
    exit 1
elif [[ "$plan_or_apply" == "plan" ]]; then
    terraform_default_options="-input=false -compact-warnings -out rundeck.tfplan"
else
    terraform_default_options="-auto-approve -input=false -compact-warnings"
fi

# Starting terraform
terraform init -upgrade
terraform workspace select default

# Compare last commits with the actual git index
git_diff=`git diff --name-status HEAD~1..HEAD | sort -u`

# Filter only projects related changes, like added, removed or renamed.
project_diff=`echo "$git_diff" \
| grep -Ev "(/jobs/.*.tfvars$|acls/.*.aclpolicy)" \
| awk '/projects/ {print $1"\t"$2"\t"$NF}' \
| sed -r 's@(^[ADRM])[0-9]+?\s+(\bprojects/[a-zA-Z0-9_-]+\b).+(\bprojects/[a-zA-Z0-9_-]+\b).+@\1 \2 \3@g' \
| uniq`

# Definitions for re-apply all projects and jobs configurations
if [[ $plan_or_apply == "re-apply" ]]; then
    plan_or_apply=apply
    git_diff=`find projects -type f -regextype egrep -regex '.*(.tfvars|/jobs/.*.ya?ml)' | sed -r 's@^(.*)@A\t\1@g'`
    project_diff=`echo "$git_diff" \
    | awk '/projects/ {print $1"\t"$2"\t"$NF}' \
    | sed -r 's@(^[ADRM])[0-9]+?\s+(\bprojects/[a-zA-Z0-9_-]+\b).+(\bprojects/[a-zA-Z0-9_-]+\b).+@\1 \2 \3@g' \
    | uniq`
fi

echo "$project_diff" | while read status changed_projects
do
    old_project_name=`awk '{print $1}' <<<$changed_projects | cut -d'/' -f2`
    project_name=`awk '{print $NF}' <<<$changed_projects | cut -d'/' -f2`

    # Migrate terraform state to the new workspace if a rename has ocurred
    # The processes is enter in the old project workspace, save the state,
    # create and enter in the new project workspace and restore the state from the old workspace.
    if [[ $status =~ ^R && "$project_name" != "$old_project_name" ]]; then
        old_tfstate="/tmp/${old_project_name}.tfstate"
        terraform workspace select $old_project_name 2>/dev/null || continue
        echo -e "- Migrating state from workspace ${old_project_name} to ${project_name}...\n"
        terraform state pull > $old_tfstate
        terraform workspace new $project_name 2> /dev/null || true
        terraform workspace select $project_name || true
        terraform state push $old_tfstate
        rm -f $old_tfstate
    fi

    # Destroy the project if it has been deleted or the dir doesn't exists anymore
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

        if [ -f "./projects/$project_name/project.properties.tfvars" ]; then
            terraform_options="
                $terraform_default_options
                -target rundeck_project.project
                -target null_resource.copy_project_files
                -var-file ./projects/$project_name/project.properties.tfvars
            "
        else
            terraform_options="
                $terraform_default_options
                -target rundeck_project.project
                -target null_resource.copy_project_files
                -var project_name=$project_name
            "
        fi

        terraform $plan_or_apply $terraform_options
    fi
done

rm -f /tmp/terraform-rundeck-*.run 2> /dev/null || true

# Jobs and acls plan or apply
echo "$git_diff" | grep -E "(/jobs/((common|${environment})/.*.(tfvars|ya?ml)$)|acls/.*.aclpolicy)" | grep -v jobs.tfvars \
| while read status changed_file
do
    project_name=`awk -F'/' '{print $2}' <<<$changed_file`
    old_job_file=`awk '{print $1}' <<<${changed_file}`
    old_job_name=`sed "s@projects/$project_name/jobs/@@g;s@/@_@g" <<<${old_job_file%%.*}`
    old_job_workspace="${project_name}_${old_job_name}"
    job_file=`awk '{print $NF}' <<<${changed_file}`
    job_name=`sed "s@projects/$project_name/jobs/@@g;s@/@_@g" <<<${job_file%%.*}`
    job_workspace="${project_name}_${job_name}"

    # Define the job config to be applied
    if [[ "$changed_file" =~ (tfvars|ya?ml) ]]; then
        if [ -f "./projects/$project_name/project.properties.tfvars" ]; then
            terraform_options="
                $terraform_default_options
                -var-file ./projects/$project_name/project.properties.tfvars
            "
        else
            terraform_options="
                $terraform_default_options
                -var project_name=$project_name
            "
        fi

        if [[ "$job_file" =~ tfvars ]]; then
            terraform_options="
                $terraform_options
                -target rundeck_job.job_workflow
                -var-file ./$job_file
            "
        else
            terraform_options="
                $terraform_options
                -target null_resource.load_job_from_yaml
                -var job_yaml_file=$job_file
            "
        fi

    # Define the acls to be applied
    # The acl have their own workspace defined as ${project_name}_acl
    # to diferentiate acls per project.
    elif [[ "$changed_file" =~ aclpolicy ]]; then
        job_name="acls"
        job_workspace="${project_name}_${job_name}"
        old_job_name=$job_name
        old_job_workspace=$job_workspace

        if [ -f "./projects/$project_name/project.properties.tfvars" ]; then
            terraform_options="
                $terraform_default_options
                -target local_file.aclpolicy
                -target rundeck_acl_policy.acl
                -var-file ./projects/$project_name/project.properties.tfvars
            "
        else
            terraform_options="
                $terraform_default_options
                -target local_file.aclpolicy
                -target rundeck_acl_policy.acl
                -var project_name=$project_name
            "
        fi
    else
        continue
    fi

    # Migrate terraform state to the new workspace if renames ocurred
    # The processes is enter in the old job workspace, save the state,
    # create and enter in the new job workspace and restore the state from the old workspace.
    if [[ $status =~ ^R ]]; then
        old_tfstate="/tmp/${old_job_name}.tfstate"
        terraform workspace select $old_job_workspace 2>/dev/null || continue

        echo -e "- Migrating state from workspace ${old_workspace} to ${workspace}...\n"
        terraform state pull > $old_tfstate
        terraform workspace new $job_workspace 2> /dev/null || true
        terraform workspace select $job_workspace || true
        terraform state push $old_tfstate
        rm -f $old_tfstate
    fi

    if [[ $status =~ ^[DR] && $plan_or_apply == "apply" ]]; then
        # Destroy the job if the definition file has been deleted
        if [[ ! -f $job_file ]]; then
            terraform workspace select $job_workspace || true
            terraform destroy $terraform_default_options
            terraform workspace select default
            terraform workspace delete $job_workspace 2>/dev/null || true
        fi

        # Only delete old job workspace in case of job rename
        terraform workspace select default
        terraform workspace delete -force $old_job_workspace 2> /dev/null || true
    fi

    # Create the job workspace and apply the job config
    if [[ $status =~ [ARM] ]]; then
        terraform workspace new $job_workspace 2> /dev/null || true
        terraform workspace select $job_workspace
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
