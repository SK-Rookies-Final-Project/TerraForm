#!/bin/bash

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# hostinfo 파일 경로
ENV_FILE="hostinfo"

# hostinfo 파일이 존재하는지 확인
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: $ENV_FILE 파일을 찾을 수 없습니다.${NC}"
    exit 1
fi

echo -e "${YELLOW}AWS EC2 인스턴스 정보를 가져오는 중...${NC}"

# AWS CLI로 인스턴스 정보 가져오기
aws_output=$(aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[?PublicIpAddress!=null].[Tags[?Key=='Name'].Value|[0],PublicIpAddress]" \
    --output text | awk '{printf "%-30s %s\n", $1, $2}')

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: AWS CLI 명령어 실행에 실패했습니다.${NC}"
    exit 1
fi

if [ -z "$aws_output" ]; then
    echo -e "${RED}Error: 실행 중인 EC2 인스턴스를 찾을 수 없습니다.${NC}"
    exit 1
fi

echo -e "${GREEN}다음 인스턴스들을 찾았습니다:${NC}"
echo "$aws_output"
echo

# 임시 파일 생성
temp_file=$(mktemp)
cp "$ENV_FILE" "$temp_file"

# AWS 출력을 파싱하여 env 파일 업데이트
echo -e "${YELLOW}=== 디버깅 정보 ===${NC}"
while read -r line; do
    if [ -n "$line" ]; then
        # 이름과 IP 추출 (공백으로 구분된 라인에서)
        name=$(echo "$line" | awk '{print $1}' | xargs)
        ip=$(echo "$line" | awk '{print $2}' | xargs)
        
        echo -e "${YELLOW}처리 중: name='$name', ip='$ip'${NC}"
        
        if [ -n "$name" ] && [ -n "$ip" ]; then
            # 이름을 대문자로 변환하고 환경변수 형식으로 변환
            env_var_name=$(echo "$name" | tr '[:lower:]' '[:upper:]' | sed 's/-/_/g')
            env_var_name="${env_var_name}_HOST"
            
            echo -e "${YELLOW}찾는 변수명: '$env_var_name'${NC}"
            
            # env 파일에서 해당 변수 찾기 (대소문자 구분 없이)
            if grep -qi "^${env_var_name}=" "$temp_file"; then
                # 기존 값이 있으면 업데이트
                old_ip=$(grep -i "^${env_var_name}=" "$temp_file" | cut -d'=' -f2)
                
                # macOS와 Linux 호환성을 위한 sed 처리
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    # macOS
                    sed -i '' "s/^${env_var_name}=.*/${env_var_name}=${ip}/" "$temp_file"
                else
                    # Linux
                    sed -i "s/^${env_var_name}=.*/${env_var_name}=${ip}/" "$temp_file"
                fi
                
                echo -e "${GREEN}✓ ${env_var_name}: ${old_ip} → ${ip}${NC}"
            else
                echo -e "${YELLOW}⚠ ${env_var_name} 변수를 env 파일에서 찾을 수 없습니다.${NC}"
                echo -e "${YELLOW}env 파일의 현재 변수들:${NC}"
                grep "^CP1_" "$temp_file" | head -5
            fi
        fi
    fi
done <<< "$aws_output"

# 변경사항 적용
mv "$temp_file" "$ENV_FILE"

echo
echo -e "${GREEN}env 파일이 성공적으로 업데이트되었습니다!${NC}"

# 업데이트된 내용 표시
echo
echo -e "${YELLOW}=== 업데이트된 env 파일 내용 ===${NC}"
cat "$ENV_FILE"