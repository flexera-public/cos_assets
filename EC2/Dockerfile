FROM fstab/aws-cli

USER root
RUN apt-get update && apt-get install -y jq

USER aws
COPY ./cpuavgs.sh /home/aws/

WORKDIR /home/aws
CMD for i in `/home/aws/aws/env/bin/aws ec2 describe-regions | jq -r '.Regions[].RegionName'`; do export AWS_DEFAULT_REGION=$i; ./cpuavgs.sh > /home/aws/output/`date +"%F"`-$i.csv; done
