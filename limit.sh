#!/bin/bash

# Cấu hình
REGIONS=("us-east-1" "us-east-2" "us-west-2")  # Thay đổi region nếu cần
NEW_QUOTA_VALUE=64   # Giá trị hạn mức mới bạn muốn
SERVICE_CODE="ec2"   # Mã dịch vụ EC2
QUOTA_CODE="L-1216C47A"  # Mã hạn mức cho Spot Instances (vCPU)

# Yêu cầu tăng hạn mức
aws service-quotas request-service-quota-increase \
    --service-code $SERVICE_CODE \
    --quota-code $QUOTA_CODE \
    --desired-value $NEW_QUOTA_VALUE \
    --region $REGION

# Kiểm tra trạng thái yêu cầu
if [ $? -eq 0 ]; then
    echo "Yêu cầu tăng hạn mức CPU cho Spot Instances đã được gửi thành công."
else
    echo "Có lỗi xảy ra khi gửi yêu cầu. Vui lòng kiểm tra lại cấu hình và quyền IAM."
fi
