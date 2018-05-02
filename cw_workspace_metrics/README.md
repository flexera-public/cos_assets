# cw_workspace_metrics
Fetches Workspace Metrics (using CloudWatch).

It goes back precisely 30 days from "today" (the default maximum history in CloudWatch) to fetch this average.

## Prerequisites
The script uses the AWS CLI, and if you follow the usage directions below, you will run a docker container that encapsulates all of the dependencies.

Therefore, the only prerequisite is AWS credentials that have access to the two API calls that the script makes via the AWS CLI.

The bare minimum permissions are described in the following IAM policy.

```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Stmt1498681025523",
      "Action": [
        "ec2:DescribeInstances"
      ],
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Sid": "Stmt1498681050464",
      "Action": [
        "cloudwatch:GetMetricStatistics"
      ],
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Sid": "Stmt1498681197818",
      "Action": [
        "ec2:DescribeRegions"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
```

## usage
Everything necessary to run the script `cw_workspace_metrics.sh` is encapsulated in the docker image which would be built by the Dockerfile.

The docker image will write the csv output to `/home/aws/output/<date>.csv` files, so if you'd like to fetch the output, make sure to map a volume there.

If you're familiar with Docker, and have it installed, you should be able to effectively do just this.
```
mkdir /tmp/output
docker build -t cw_workspace_metrics .
docker run --rm -it -e AWS_DEFAULT_REGION=us-east-1 -e AWS_ACCESS_KEY_ID=<your access key id> -e AWS_SECRET_ACCESS_KEY=<your access key> -v /tmp/output:/home/aws/output:rw cw_workspace_metrics
```
