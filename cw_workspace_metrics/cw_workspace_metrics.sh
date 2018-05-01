#!/usr/bin/env bash

export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-west-2}
start_time=$(date --date="30 days ago" +"%Y-%m-%dT00:00:00Z")
end_time=$(date +"%Y-%m-%dT00:00:00Z")

if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
  >&2 echo "No AWS credentials provided, please set environment variables named AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
  exit 1
fi

for i in `/home/aws/aws/env/bin/aws ec2 describe-regions | jq -r '.Regions[].RegionName'`
do
  export AWS_DEFAULT_REGION=$i
  metrics=$(/home/aws/aws/env/bin/aws cloudwatch get-metric-statistics --namespace AWS/WorkSpaces --metric-name UserConnected --start-time "$start_time" --end-time "$end_time" --period 1209600 --statistic Average Sum Maximum Minimum)
  record_count=$(echo $metrics | jq '.Datapoints|length-1')
done
