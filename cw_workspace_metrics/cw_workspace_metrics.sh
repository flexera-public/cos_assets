#!/usr/bin/env bash
set +x
aws=$(which aws)
if [ -z "$aws" ]; then
  aws='/home/aws/aws/env/bin/aws'
fi

export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}
start_time=$(date --date="30 days ago" +"%Y-%m-%dT00:00:00Z")
end_time=$(date +"%Y-%m-%dT00:00:00Z")

if [[ -z "$AWS_ACCESS_KEY_ID" && -z "$AWS_SECRET_ACCESS_KEY" && "$($aws configure list | awk '/access_key/ {print $2}')" == '<not' ]]; then
  >&2 echo "No AWS credentials provided, please set environment variables named AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
  exit 1
fi
echo "Region,WorkspaceId,Average,Sum,Maximum,Minimum"
if [ -z "$AWS_DEFAULT_REGION" ]; then
  for i in `$aws ec2 describe-regions | jq -r '.Regions[].RegionName'`
  do
    export AWS_DEFAULT_REGION=$i
    workspaces=$($aws workspaces describe-workspaces | jq -r '.Workspaces[].WorkspaceId')
    for workspace in $workspaces; do
      metrics=$($aws cloudwatch get-metric-statistics --namespace AWS/WorkSpaces --metric-name UserConnected --start-time "$start_time" --end-time "$end_time" --period 1209600 --statistic Average Sum Maximum Minimum --dimensions Name=WorkspaceId,Value=$workspace)
      record_count=$(echo $metrics | jq '.Datapoints|length-1')
      echo "$AWS_DEFAULT_REGION-$workspace-$metrics-$record_count"
    done
  done
else
  workspaces=$($aws workspaces describe-workspaces | jq -r '.Workspaces[].WorkspaceId')
  for workspace in $workspaces; do
    metrics=$($aws cloudwatch get-metric-statistics --namespace AWS/WorkSpaces --metric-name UserConnected --start-time "$start_time" --end-time "$end_time" --period 1209600 --statistic Average Sum Maximum Minimum --dimensions Name=WorkspaceId,Value=$workspace)
    record_count=$(echo $metrics | jq '.Datapoints|length-1')
    average=$(echo $metrics | jq ".Datapoints|=sort_by(.Timestamp)|.Datapoints[0].Average")
    sum=$(echo $metrics | jq ".Datapoints|=sort_by(.Timestamp)|.Datapoints[0].Sum")
    max=$(echo $metrics | jq ".Datapoints|=sort_by(.Timestamp)|.Datapoints[0].Maximum")
    min=$(echo $metrics | jq ".Datapoints|=sort_by(.Timestamp)|.Datapoints[0].Minimum")
    echo "$AWS_DEFAULT_REGION,$workspace,$average,$sum,$max,$min"
  done
fi
