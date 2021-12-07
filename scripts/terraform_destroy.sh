#!/bin/bash

terraform workspace select default

terraform workspace list | grep -Ev '(\*|default|^$)' | while read workspace
do
    terraform workspace select $workspace
    terraform destroy -auto-approve
    terraform workspace select default
    terraform workspace delete -force $workspace
done
