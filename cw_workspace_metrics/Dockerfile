FROM fstab/aws-cli

USER root
RUN apt-get update && apt-get install -y jq

COPY ./cw_workspace_metrics.sh /home/aws/
RUN chown aws /home/aws/cw_workspace_metrics.sh && chmod +x /home/aws/cw_workspace_metrics.sh && mkdir -p /home/aws/output/ && chown aws /home/aws/output
USER aws

WORKDIR /home/aws
CMD ./cw_workspace_metrics.sh | tee /home/aws/output/`date +"%F"`.csv
