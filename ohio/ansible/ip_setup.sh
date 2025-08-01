#!/bin/bash

# AWS EC2 인스턴스 정보를 기반으로 Ansible inventory.ini 파일을 생성하는 스크립트

# 설정
INVENTORY_FILE="inventory.ini"
AWS_REGION=${AWS_DEFAULT_REGION:-"us-east-2"}  # 기본값: 서울 리전

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# AWS CLI 설치 확인
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI가 설치되어 있지 않습니다."
        log_error "설치 방법: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    log_info "AWS CLI가 설치되어 있습니다."
}

# AWS 자격 증명 확인
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS 자격 증명이 설정되어 있지 않습니다."
        log_error "aws configure 명령을 사용하여 자격 증명을 설정하세요."
        exit 1
    fi
    log_info "AWS 자격 증명이 확인되었습니다."
}

# inventory.ini 파일 헤더 생성
create_inventory_header() {
    cat > "$INVENTORY_FILE" << EOF
# Ansible Inventory File
# 자동 생성됨: $(date)
# AWS 리전: $AWS_REGION

EOF
}

# EC2 인스턴스 정보 조회 및 inventory 생성
generate_inventory() {
    log_info "AWS 리전 '$AWS_REGION'에서 실행 중인 EC2 인스턴스를 조회합니다..."
    
    # AWS CLI를 사용하여 실행 중인 인스턴스 정보 조회
    instances=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=instance-state-name,Values=running" \
        --query 'Reservations[*].Instances[*].[Tags[?Key==`Name`].Value|[0],PublicIpAddress,InstanceId,InstanceType,PrivateIpAddress]' \
        --output text)
    
    if [ -z "$instances" ]; then
        log_warn "실행 중인 EC2 인스턴스가 없습니다."
        echo "# 실행 중인 인스턴스가 없습니다." >> "$INVENTORY_FILE"
        return
    fi
    
    # 그룹별로 인스턴스 분류
    declare -A groups
    instance_count=0
    
    while IFS=$'\t' read -r name public_ip instance_id instance_type private_ip; do
        # None 값 처리
        if [ "$name" = "None" ] || [ -z "$name" ]; then
            name="unnamed-$instance_id"
        fi
        
        if [ "$public_ip" = "None" ] || [ -z "$public_ip" ]; then
            log_warn "인스턴스 '$name' ($instance_id)에 퍼블릭 IP가 없습니다. 프라이빗 IP를 사용합니다."
            ip_address="$private_ip"
        else
            ip_address="$public_ip"
        fi
        
        # 인스턴스 타입을 기반으로 그룹 결정
        group_name=$(echo "$instance_type" | cut -d'.' -f1)
        
        # 그룹에 인스턴스 추가
        if [ -z "${groups[$group_name]}" ]; then
            groups[$group_name]="$name ansible_host=$ip_address ansible_ssh_user=ubuntu"
        else
            groups[$group_name]="${groups[$group_name]}"$'\n'"$name ansible_host=$ip_address ansible_ssh_user=ubuntu"
        fi
        
        instance_count=$((instance_count + 1))
        log_info "인스턴스 추가: $name ($ip_address)"
    done <<< "$instances"
    
    # inventory 파일에 전체 인스턴스 목록 작성
    echo "# 모든 EC2 인스턴스" >> "$INVENTORY_FILE"
    echo "" >> "$INVENTORY_FILE"
    
    echo "[webservers]" >> "$INVENTORY_FILE"
    for group in "${!groups[@]}"; do
        echo "${groups[$group]}" >> "$INVENTORY_FILE"
    done
    echo "" >> "$INVENTORY_FILE"
    
    # 그룹 메타 정보
    echo "[webservers:vars]" >> "$INVENTORY_FILE"
    echo "ansible_ssh_private_key_file=~/Desktop/ct/common/test-key.pem" >> "$INVENTORY_FILE"
    echo "ansible_ssh_common_args='-o StrictHostKeyChecking=no'" >> "$INVENTORY_FILE"
    echo "" >> "$INVENTORY_FILE"
    
    log_info "총 $instance_count개의 인스턴스가 inventory에 추가되었습니다."
}

# 메인 함수
main() {
    log_info "AWS EC2 Ansible Inventory 생성 스크립트를 시작합니다."
    
    # 명령행 인수 처리
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -o|--output)
                INVENTORY_FILE="$2"
                shift 2
                ;;
            -h|--help)
                echo "사용법: $0 [옵션]"
                echo "옵션:"
                echo "  -r, --region REGION    AWS 리전 지정 (기본값: ap-northeast-2)"
                echo "  -o, --output FILE      출력 파일명 지정 (기본값: inventory.ini)"
                echo "  -h, --help            도움말 표시"
                exit 0
                ;;
            *)
                log_error "알 수 없는 옵션: $1"
                echo "도움말을 보려면 $0 --help 를 실행하세요."
                exit 1
                ;;
        esac
    done
    
    # 사전 검사
    check_aws_cli
    check_aws_credentials
    
    # inventory 파일 생성
    create_inventory_header
    generate_inventory
    
    log_info "Ansible inventory 파일이 생성되었습니다: $INVENTORY_FILE"
    log_info "파일 내용을 확인하려면: cat $INVENTORY_FILE"
    log_info "Ansible에서 사용하려면: ansible all -i $INVENTORY_FILE --list-hosts"
}

# 스크립트 실행
main "$@"