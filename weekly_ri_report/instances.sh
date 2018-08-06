#!/usr/bin/env bash

set -e
#set -x

#defaults
API_HOST="us-4"
REFRESH_TOKEN=""
START_TIME="2018-07-15T00:00:00"
END_TIME="2018-07-30T23:59:00"
ACCOUNT_IDS="" #"106220"
TIMEZONE="America/Los_Angeles"
TIMESTAMP=$( date "+%Y%m%d%H%M%S" )

help(){
  echo "Usage: $0 [option...] "
  echo "-e email                your rightscale email "
  echo "-p password             your rightscale password"
  echo "-r refresh_token        your rightscale refresh token"
  echo "-H us-4                 rightscale host, us-4, us-3, telstra-1-"
  echo "-a "12345 67890 ..."    list of rightscale account ids, space delimited"
  echo "-z TIMEZONE             filter timezone. defaults to America/Los_Angeles"
  echo "-S 2018-7-15T00:00:00   filter start time"
  echo "-E 2018-7-30T00:00:00   filter end time"
}

for i in "$@"
do
case $i in
   -e)
   EMAIL=$2
   shift 2
   ;;
   -p)
   PASSWORD=$2
   shift 2
   ;;
   -r)
   REFRESH_TOKEN=$2
   shift 2
   ;;
   -H)
   API_HOST=$2
   shift 2
   ;;
   -a)
   ACCOUNT_IDS=($2)
   shift 2
   ;;
   -z)
   timezone=$2
   shift 2
   ;;
   -S)
   START_TIME=$2
   shift 2
   ;;
   -E)
   END_TIME=$2
   shift 2
   ;;
   -h)
   help
   exit 0
   ;;
   *)

   ;;
esac
done

my_token_endpoint="https://$API_HOST.rightscale.com/api/oauth2"

# create JSON array of instance_filters for export
declare -a instance_filters
for (( i=0; i<${#ACCOUNT_IDS[@]}; i++ ));do
  item="{\"type\":\"instance:account_id\",\"value\":\"${ACCOUNT_IDS[$i]}\"}"
  instance_filters=(${instance_filters[@]} $item)
done
instance_filters_json=$(printf '%s\n' ${instance_filters[@]} | jq -R . | jq -s .)
instance_filters_json=$(eval echo $instance_filters_json)

#main
# get access_token
if [ -n "$REFRESH_TOKEN" ];then
  access_token=$(curl -H "X-API-Version:1.5" --request POST "$my_token_endpoint"  \
       -d "grant_type=refresh_token"  -d "refresh_token=$REFRESH_TOKEN" | jq -r '.access_token')
  AUTH_OPTION="-H \"Authorization: Bearer $access_token\""
  #AUTH_OPTION=$(echo -e ${AUTH_OPTION})
  AUTH_OPTION=$(printf "%s" -H "Authorization:Bearer $access_token")
else
  if [ -z "$EMAIL" ];then
    echo "Refresh token or Email and/or Password is missing."
    help
    exit 1
  fi
  curl -H X_API_VERSION:1.5 -c mycookie -X POST --data-urlencode "email=$EMAIL" \
  --data-urlencode "password=$PASSWORD" -d account_href=/api/accounts/"${ACCOUNT_IDS[0]}" https://$API_HOST.rightscale.com/api/session
  AUTH_OPTION=$(printf "%s" "-b mycookie")
fi

if [ -z "$ACCOUNT_IDS[@]" ];then
  echo "missing account id's to filter"
  help
  exit 1
fi
echo "---> Authenticated with RightScale"
# # export instances
echo "---> Exporting Instances"
curl -H "X-API-Version:1.0" $AUTH_OPTION  \
  -H Content-Type:text/json \
  -o instances-$TIMESTAMP.csv \
  -d "{\"start_time\":\"$START_TIME\",\"end_time\":\"$END_TIME\",\"timezone\":\"$TIMEZONE\",\"instance_filters\":$instance_filters_json}"\
  https://analytics.rightscale.com/api/instances/actions/export
echo "---> Instances export complete.  See file instances-$TIMESTAMP.csv"
#export reserved_instances
echo "---> Exporting Reserved Instances"
curl  -H "X-API-Version:1.0" $AUTH_OPTION  \
  -H Content-Type:text/json \
  -o ri-$TIMESTAMP.csv \
  -d "{\"start_time\":\"$START_TIME\",\"end_time\":\"$END_TIME\",\"timezone\":\"$TIMEZONE\",\"reserved_instance_filters\":$instance_filters_json}"\
  https://analytics.rightscale.com/api/reserved_instances/actions/export
  echo "---> Reserved Instances export complete.  See file ri-$TIMESTAMP.csv"
