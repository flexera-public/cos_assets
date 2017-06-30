#!/usr/bin/env bash

export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-west-2}
start_time=$(date --date="14 days ago" +"%Y-%m-%dT00:00:00Z")
end_time=$(date +"%Y-%m-%dT00:00:00Z")

if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
  >&2 echo "No AWS credentials provided, please set environment variables named AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
  exit 1
fi

>&2 echo "Finding the total average CPU use for each instance in $AWS_DEFAULT_REGION, between $start_time and $end_time"

instances=$(/home/aws/aws/env/bin/aws ec2 describe-instances)
instance_ids=$(echo $instances | jq -r '.Reservations[].Instances[].InstanceId')

>&2 echo "Found these instances"
>&2 echo $instance_ids

for instance_id in $instance_ids; do
	    >&2 echo "Getting cpu metrics for instance: $instance_id"
	    metrics=$(/home/aws/aws/env/bin/aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization --start-time "$start_time" --end-time "$end_time" --period 1209600 --statistic Average Maximum --dimensions Name=InstanceId,Value=$instance_id)
	    record_count=$(echo $metrics | jq '.Datapoints|length-1')
	    
	    for cpu in $(seq 0 $record_count); do
		cpu_avg=$(echo $metrics | jq ".Datapoints|=sort_by(.Timestamp)|.Datapoints[$cpu].Average")	 
		cpu_max=$(echo $metrics | jq ".Datapoints|=sort_by(.Timestamp)|.Datapoints[$cpu].Maximum")
	    echo "$instance_id,$cpu_avg,$cpu_max"
	    done
done
