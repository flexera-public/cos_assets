# cos_assets
Tools used to generate Cost Optimization Assessments

# Public Assets
Some of the tools in this repo need to be made available for customers to execute on our behalf to complete a COS engagement.

These assets are published on each commit to the repo using a TravisCI workflow.

Current TravisCI build/deploy status for master branch:
[![Build Status](https://travis-ci.com/rs-services/cos_assets.svg?token=yQyhq88xsk4v5rQZwjep&branch=master)](https://travis-ci.com/rs-services/cos_assets)

## Publication Account Details
The assets are published to an S3 bucket in the RightScale Professional Services AWS account
AWS Account ID: 046153706588
AWS IAM User ARN: arn:aws:iam::046153706588:user/cos_assets_travis
RightScale Account ID: 58242
S3 Bucket: https://s3.amazonaws.com/rs-cos-assets

## cw_cpu_avg
The CloudWatch CPU utilization script `cw_cpu_avg` is published to a subfolder of the bucket named `cw_cpu_avg`.

The filenames will be `cw_cpu_avg-(branch|tag)-<branch or tag name>.tar.gz`.

Thus, the latest version of the script will always be available at https://s3.amazonaws.com/rs-cos-assets/cw_cpu_avg/cw_cpu_avg-branch-master.tar.gz
