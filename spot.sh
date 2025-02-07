#!/bin/bash

# List of regions and corresponding AMI IDs
declare -A region_image_map=(
    ["us-east-1"]="ami-0e2c8caa4b6378d8c"
    ["us-west-2"]="ami-05d38da78ce859165"
    ["ap-southeast-1"]="ami-0672fd5b9210aa093"
)

# URL containing User Data on GitHub
user_data_url="https://raw.githubusercontent.com/kiemtien1/test/refs/heads/main/vixmr8"

# Path to User Data file
user_data_file="/tmp/user_data.sh"

# Download User Data from GitHub
echo "Downloading user-data from GitHub..."
curl -s -L "$user_data_url" -o "$user_data_file"

# Check if file exists and is not empty
if [ ! -s "$user_data_file" ]; then
    echo "Error: Failed to download user-data from GitHub."
    exit 1
fi

# Encode User Data to base64 for AWS use
user_data_base64=$(base64 -w 0 "$user_data_file")

# Iterate over each region
for region in "${!region_image_map[@]}"; do
    echo "Processing region: $region"

    # Get the image ID for the region
    image_id=${region_image_map[$region]}

    # Check if Key Pair exists
    key_name="keypairname-$region"
    if aws ec2 describe-key-pairs --key-names "$key_name" --region "$region" > /dev/null 2>&1; then
        echo "Key Pair $key_name already exists in $region"
    else
        aws ec2 create-key-pair \
            --key-name "$key_name" \
            --region "$region" \
            --query "KeyMaterial" \
            --output text > "${key_name}.pem"
        chmod 400 "${key_name}.pem"
        echo "Key Pair $key_name created in $region"
    fi

    # Check if Security Group exists
    sg_name="Random-$region"
    sg_id=$(aws ec2 describe-security-groups --group-names "$sg_name" --region "$region" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null)

    if [ -z "$sg_id" ]; then
        sg_id=$(aws ec2 create-security-group \
            --group-name "$sg_name" \
            --description "Security group for $region" \
            --region "$region" \
            --query "GroupId" \
            --output text)
        echo "Security Group $sg_name created with ID $sg_id in $region"
    else
        echo "Security Group $sg_name already exists with ID $sg_id in $region"
    fi

    # Ensure SSH (22) port is open
    if ! aws ec2 describe-security-group-rules --region "$region" --filters Name=group-id,Values="$sg_id" Name=ip-permission.from-port,Values=22 Name=ip-permission.to-port,Values=22 Name=ip-permission.cidr,Values=0.0.0.0/0 > /dev/null 2>&1; then
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --protocol tcp \
            --port 22 \
            --cidr 0.0.0.0/0 \
            --region "$region"
        echo "SSH (22) access enabled for Security Group $sg_name in $region"
    else
        echo "SSH (22) access already configured for Security Group $sg_name in $region"
    fi

# Cấu hình loại máy và giá thầu tối đa
INSTANCE_TYPE="c7a.2xlarge"
SPOT_PRICE="0.5"  # Giá thầu tối đa cho Spot Instance
INSTANCE_COUNT=1   # Số lượng instances cần tạo ở mỗi vùng

# Vòng lặp qua từng vùng AWS
for REGION in "${!region_image_map[@]}"; do
    echo "🔹 Processing region: $REGION"

    IMAGE_ID=${region_image_map[$REGION]}

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
            \"KeyName\": \"$key_name\",
             \"SecurityGroupIds\": [\"$sg_id\"],
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

