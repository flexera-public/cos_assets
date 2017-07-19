FROM fstab/aws-cli

USER root
RUN apt-get update && apt-get install -y jq
COPY ./cw_cpu_avg.sh /home/aws/
RUN chown aws /home/aws/cw_cpu_avg.sh && chmod +x /home/aws/cw_cpu_avg.sh

USER aws

WORKDIR /home/aws
CMD ./cw_cpu_avg.sh | tee /home/aws/output/`date +"%F"`.csv
