cd seoul
terraform init
terraform plan -var-file="../common/terraform.tfvars"
terraform apply -var-file="../common/terraform.tfvars"

cd ../ansible-ec2
sh inventory.sh

ansible-playbook -i inventory.ini packages.yml