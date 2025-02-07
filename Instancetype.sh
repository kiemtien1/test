#!/bin/bash
REGION="us-east-1" "us-west-2" "eu-central-1"

# Dừng instance
aws ec2 stop-instances --instance-ids $INSTANCE_ID --region $REGION
aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID --region $REGION

# Lấy thông tin hiện tại
CURRENT_TYPE=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query "Reservations[0].Instances[0].InstanceType" --output text)

# Chọn loại instance mới (ví dụ: tăng lên gấp đôi)
NEW_TYPE="c7a.2xlarge"
if [ "$CURRENT_TYPE" == "c7a.2xlarge" ]; then
    NEW_TYPE="c7a.large"
fi

# Đổi Instance Type
aws ec2 modify-instance-attribute --instance-id $INSTANCE_ID --instance-type "{\"Value\": \"$NEW_TYPE\"}" --region $REGION

# Khởi động lại
aws ec2 start-instances --instance-ids $INSTANCE_ID --region $REGION

echo "Instance $INSTANCE_ID đã đổi sang loại $NEW_TYPE và được khởi động lại!"
