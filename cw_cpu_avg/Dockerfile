FROM fstab/aws-cli

USER root
RUN apt-get update && apt-get install -y jq
COPY ./cw_cpu_avg.sh /home/aws/
RUN chown aws /home/aws/cw_cpu_avg.sh && chmod +x /home/aws/cw_cpu_avg.sh

USER aws

WORKDIR /home/aws
CMD for i in `/home/aws/aws/env/bin/aws ec2 describe-regions | jq -r '.Regions[].RegionName'`; do export AWS_DEFAULT_REGION=$i; ./cw_cpu_avg.sh > /home/aws/output/`date +"%F"`-$i.csv; done
