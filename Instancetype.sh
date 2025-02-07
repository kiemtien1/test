#!/bin/bash

# Danh sách vùng cần thay đổi
REGIONS=("us-east-1" "us-west-2" "eu-central-1")

# Quy tắc nâng cấp Instance Type
upgrade_instance_type() {
    case "$1" in
        "c7a.2xlarge") echo "c7a.large" ;;
        "c7a.4xlarge") echo "c7a.8xlarge" ;;
        "c7a.8xlarge") echo "c7a.16xlarge" ;;
        *) echo "$1" ;;  # Không thay đổi nếu không có trong danh sách
    esac
}

# Lặp qua từng vùng
for REGION in "${REGIONS[@]}"; do
    echo "🔍 Đang kiểm tra Instance trong vùng $REGION..."

    # Lấy danh sách tất cả Instance đang chạy
    INSTANCE_INFO=$(aws ec2 describe-instances --region $REGION --query "Reservations[*].Instances[*].[InstanceId,InstanceType]" --output text)

    if [ -z "$INSTANCE_INFO" ]; then
        echo "✅ Không có Instance nào chạy trong vùng $REGION."
        continue
    fi

    # Lặp qua từng Instance
    while read -r INSTANCE_ID CURRENT_TYPE; do
        echo "🛑 Dừng Instance $INSTANCE_ID ($CURRENT_TYPE)..."
        aws ec2 stop-instances --instance-ids $INSTANCE_ID --region $REGION
    done <<< "$INSTANCE_INFO"

    echo "⏳ Chờ tất cả Instance dừng..."
    aws ec2 wait instance-stopped --region $REGION

    # Lặp lại để thay đổi Instance Type
    while read -r INSTANCE_ID CURRENT_TYPE; do
        NEW_TYPE=$(upgrade_instance_type "$CURRENT_TYPE")
        if [ "$NEW_TYPE" != "$CURRENT_TYPE" ]; then
            echo "🔄 Thay đổi Instance $INSTANCE_ID từ $CURRENT_TYPE → $NEW_TYPE..."
            aws ec2 modify-instance-attribute --instance-id $INSTANCE_ID --instance-type "{\"Value\": \"$NEW_TYPE\"}" --region $REGION
        else
            echo "⚠️ Instance $INSTANCE_ID giữ nguyên loại: $CURRENT_TYPE"
        fi
    done <<< "$INSTANCE_INFO"

    # Khởi động lại tất cả Instance
    while read -r INSTANCE_ID CURRENT_TYPE; do
        echo "🚀 Khởi động lại Instance $INSTANCE_ID..."
        aws ec2 start-instances --instance-ids $INSTANCE_ID --region $REGION
    done <<< "$INSTANCE_INFO"

    echo "✅ Hoàn tất thay đổi Instance trong vùng $REGION."
done

echo "🎉 Tất cả Instance đã được cập nhật thành công!"
