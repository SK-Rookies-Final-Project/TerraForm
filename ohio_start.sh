cd ohio
terraform init
terraform plan -var-file="../common/terraform.tfvars"
terraform apply -auto-approve -var-file="../common/terraform.tfvars"

cd ansible
sh ip_setup.sh

ansible-playbook -i inventory.ini docker-install-playbook.yml