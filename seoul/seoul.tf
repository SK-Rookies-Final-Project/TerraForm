# Terraform 설정
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# AWS Provider 설정 - 서울 리전
provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = "ap-northeast-2"
}

# 기존 VPC 참조 (미리 생성된 VPC 사용)
data "aws_vpc" "custom" {
  id = "vpc-073a072bc881801a6"
}

# 사용자 정의 VPC의 서브넷 조회
data "aws_subnets" "custom" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.custom.id]
  }
}

# Ubuntu 22.04 LTS AMI 조회
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# 키 페어 존재 확인을 위한 data source
data "aws_key_pair" "existing_key" {
  key_name           = "test-key"
  include_public_key = true
}

# 조건부 키 페어 생성 - 존재하지 않을 때만 생성
resource "aws_key_pair" "test_key" {
  count      = data.aws_key_pair.existing_key.key_name == null ? 1 : 0
  key_name   = "test-key"
  public_key = tls_private_key.test_key[0].public_key_openssh
}

# 조건부 private key 생성 - 키 페어가 존재하지 않을 때만 생성
resource "tls_private_key" "test_key" {
  count     = data.aws_key_pair.existing_key.key_name == null ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# 조건부 private key 파일 저장 - 키 페어가 존재하지 않을 때만 생성
resource "local_file" "test_key_pem" {
  count           = data.aws_key_pair.existing_key.key_name == null ? 1 : 0
  content         = tls_private_key.test_key[0].private_key_pem
  filename        = "../common/test-key.pem"
  file_permission = "0600"
}

# 기존 키 파일 읽기 - 키 페어가 존재할 때만 사용
data "local_file" "existing_private_key" {
  count    = data.aws_key_pair.existing_key.key_name != null ? 1 : 0
  filename = "../common/test-key.pem"
}

# EC2 보안 그룹 존재 확인
data "aws_security_groups" "existing_ec2_sg" {
  filter {
    name   = "group-name"
    values = ["ec2-security-group"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.custom.id]
  }
}

# 조건부 EC2 보안 그룹 생성 - 존재하지 않을 때만 생성
resource "aws_security_group" "ec2_security_group" {
  count       = length(data.aws_security_groups.existing_ec2_sg.ids) == 0 ? 1 : 0
  name        = "ec2-security-group"
  description = "Security group for EC2 instances with all TCP access"
  vpc_id      = data.aws_vpc.custom.id

  # SSH 접근 허용
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 모든 TCP 포트 허용 (인스턴스 간 통신)
  ingress {
    description = "All TCP traffic"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 모든 아웃바운드 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-security-group"
  }
}

# RDS 보안 그룹 존재 확인
data "aws_security_groups" "existing_rds_sg" {
  filter {
    name   = "group-name"
    values = ["rds-security-group"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.custom.id]
  }
}

# 조건부 RDS 보안 그룹 생성 - 존재하지 않을 때만 생성
resource "aws_security_group" "rds_security_group" {
  count       = length(data.aws_security_groups.existing_rds_sg.ids) == 0 ? 1 : 0
  name        = "rds-security-group"
  description = "Security group for RDS instances"
  vpc_id      = data.aws_vpc.custom.id

  # MySQL 포트
  ingress {
    description = "MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # PostgreSQL 포트
  ingress {
    description = "PostgreSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 모든 아웃바운드 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-security-group"
  }
}

# locals 블록 추가 - 조건부 리소스 참조를 위한 로컬 값 정의
locals {
  # 키 페어 이름 결정
  key_name = data.aws_key_pair.existing_key.key_name != null ? data.aws_key_pair.existing_key.key_name : aws_key_pair.test_key[0].key_name
  
  # 보안 그룹 ID 결정
  ec2_security_group_id = length(data.aws_security_groups.existing_ec2_sg.ids) > 0 ? data.aws_security_groups.existing_ec2_sg.ids[0] : aws_security_group.ec2_security_group[0].id
  rds_security_group_id = length(data.aws_security_groups.existing_rds_sg.ids) > 0 ? data.aws_security_groups.existing_rds_sg.ids[0] : aws_security_group.rds_security_group[0].id
}


data "aws_security_group" "ec2_security_group" {
  filter {
    name   = "group-name"
    values = ["ec2-security-group"]
  }
}

data "aws_security_group" "rds_security_group" {
  filter {
    name   = "group-name"
    values = ["rds-security-group"]
  }
  # 또는 직접 ID 지정 가능
  # id = "sg-xxxxxx"
}

# EC2 인스턴스들
# Controller 인스턴스 (t3.medium) - 3대
resource "aws_instance" "controller" {
  count                  = 3
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  key_name              = local.key_name
  vpc_security_group_ids = [local.ec2_security_group_id]
  subnet_id             = "subnet-0b9632f3f4689f54a"
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp2"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "CP1_Controller${count.index + 1}_A"
    Type = "Controller"
  }
}

# Broker 인스턴스 (t3.large) - 3대
resource "aws_instance" "broker" {
  count                  = 3
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.large"
  key_name              = local.key_name
  vpc_security_group_ids = [local.ec2_security_group_id]
  subnet_id             = "subnet-0b9632f3f4689f54a"
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp2"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = count.index == 0 ? "CP1_Broker1_A" : count.index == 1 ? "CP1_Broker2_A" : "CP1_Broker3_A"
    Type = "Broker"
  }
}

# Connect Worker 인스턴스 (t3.medium) - 2대
resource "aws_instance" "connect_worker" {
  count                  = 2
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  key_name              = local.key_name
  vpc_security_group_ids = [local.ec2_security_group_id]
  subnet_id             = "subnet-0b9632f3f4689f54a"
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp2"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "CP1_Connect${count.index + 1}_A"
    Type = "Connect-Worker"
  }
}

# Schema Registry 인스턴스 (t3.small) - 2대
resource "aws_instance" "schema_registry" {
  count                  = 2
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  key_name              = local.key_name
  vpc_security_group_ids = [local.ec2_security_group_id]
  subnet_id             = "subnet-0b9632f3f4689f54a"
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp2"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "CP1_SR${count.index + 1}_A"
    Type = "Schema-Registry"
  }
}

# Confluent Control Center 인스턴스 (t3.large) - 1대
resource "aws_instance" "control_center" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.large"
  key_name              = local.key_name
  vpc_security_group_ids = [local.ec2_security_group_id]
  subnet_id             = "subnet-0b9632f3f4689f54a"
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp2"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "CP1_C3_A"
    Type = "Control-Center"
  }
}

# EIP 할당 - Broker 3개
resource "aws_eip" "broker_eip" {
  count    = 3
  instance = aws_instance.broker[count.index].id
  domain   = "vpc"

  tags = {
    Name = "Broker${count.index + 1}-EIP"
  }

  depends_on = [aws_instance.broker]
}

# EIP 할당 - Schema Registry 2개
resource "aws_eip" "schema_registry_eip" {
  count    = 2
  instance = aws_instance.schema_registry[count.index].id
  domain   = "vpc"

  tags = {
    Name = "Schema-Registry${count.index + 1}-EIP"
  }

  depends_on = [aws_instance.schema_registry]
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = data.aws_subnets.custom.ids

  tags = {
    Name = "RDS Subnet Group"
  }
}

# Amazon RDS for MySQL
resource "aws_db_instance" "mysql" {
  identifier = "tgmysqldb"
  
  # 엔진 설정
  engine         = "mysql"
  engine_version = "8.0"
  
  # 인스턴스 클래스
  instance_class = "db.t3.micro"
  
  # 스토리지 설정
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type         = "gp2"
  storage_encrypted    = true
  
  # 데이터베이스 설정
  db_name  = "tgmysqlDB"
  username = "tgadmin"
  password = "tgmaster!"
  
  # 네트워크 설정 - RDS 전용 보안 그룹 사용
  vpc_security_group_ids = [local.rds_security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  publicly_accessible    = true
  
  # 파라미터 및 옵션 그룹
  parameter_group_name = "default.mysql8.0"
  option_group_name    = "default:mysql-8-0"
  
  # 백업 설정
  backup_retention_period = 0
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  # 기타 설정
  skip_final_snapshot = true
  deletion_protection = false
  
  tags = {
    Name = "tgmysqldb"
    Type = "MySQL"
  }
}

# Amazon RDS for PostgreSQL
resource "aws_db_instance" "postgresql" {
  identifier = "tgpostgresql"
  
  # 엔진 설정
  engine         = "postgres"
  engine_version = "16.3"
  
  # 인스턴스 클래스
  instance_class = "db.t4g.micro"
  
  # 스토리지 설정
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type         = "gp3"
  storage_encrypted    = true
  
  # 데이터베이스 설정
  db_name  = "tgpostgreDB"
  username = "tgadmin"
  password = "tgmaster!"
  
  # 네트워크 설정 - RDS 전용 보안 그룹 사용
  vpc_security_group_ids = [local.rds_security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  publicly_accessible    = true
  
  # 파라미터 그룹
  parameter_group_name = "default.postgres16"
  
  # 백업 설정
  backup_retention_period = 0
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  # 기타 설정
  skip_final_snapshot = true
  deletion_protection = false
  
  tags = {
    Name = "tgpostgresql"
    Type = "PostgreSQL"
  }
}

# Outputs
output "vpc_id" {
  description = "사용된 VPC ID"
  value = data.aws_vpc.custom.id
}

output "subnet_ids" {
  description = "사용된 서브넷 ID들"
  value = data.aws_subnets.custom.ids
}

output "controller_instances" {
  description = "Controller 인스턴스 정보"
  value = {
    for i, instance in aws_instance.controller : 
    instance.tags.Name => {
      instance_id = instance.id
      private_ip  = instance.private_ip
      public_ip   = instance.public_ip
      subnet_id   = instance.subnet_id
    }
  }
}

output "broker_instances" {
  description = "Broker 인스턴스 정보 (EIP 포함)"
  value = {
    for i, instance in aws_instance.broker : 
    instance.tags.Name => {
      instance_id = instance.id
      private_ip  = instance.private_ip
      public_ip   = instance.public_ip
      eip         = aws_eip.broker_eip[i].public_ip
      subnet_id   = instance.subnet_id
    }
  }
}

output "connect_worker_instances" {
  description = "Connect Worker 인스턴스 정보"
  value = {
    for i, instance in aws_instance.connect_worker : 
    instance.tags.Name => {
      instance_id = instance.id
      private_ip  = instance.private_ip
      public_ip   = instance.public_ip
      subnet_id   = instance.subnet_id
    }
  }
}

output "schema_registry_instances" {
  description = "Schema Registry 인스턴스 정보 (EIP 포함)"
  value = {
    for i, instance in aws_instance.schema_registry : 
    instance.tags.Name => {
      instance_id = instance.id
      private_ip  = instance.private_ip
      public_ip   = instance.public_ip
      eip         = aws_eip.schema_registry_eip[i].public_ip
      subnet_id   = instance.subnet_id
    }
  }
}

output "control_center_instance" {
  description = "Control Center 인스턴스 정보"
  value = {
    instance_id = aws_instance.control_center.id
    private_ip  = aws_instance.control_center.private_ip
    public_ip   = aws_instance.control_center.public_ip
    subnet_id   = aws_instance.control_center.subnet_id
  }
}

output "mysql_endpoint" {
  description = "MySQL RDS 엔드포인트"
  value = aws_db_instance.mysql.endpoint
}

output "postgresql_endpoint" {
  description = "PostgreSQL RDS 엔드포인트"
  value = aws_db_instance.postgresql.endpoint
}

output "private_key_path" {
  description = "SSH 접근을 위한 Private Key 경로"
  value       = "../common/test-key.pem"
}