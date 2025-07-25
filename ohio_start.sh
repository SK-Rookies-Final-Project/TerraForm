cd ohio
terraform init
terraform plan -var-file="../common/terraform.tfvars"
terraform apply -auto-approve -var-file="../common/terraform.tfvars"