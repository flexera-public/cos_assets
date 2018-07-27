#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

d_account_id="missing"
d_start=$(date -v-32d +%Y-%m-%d)
d_end=$(date -v-2d +%Y-%m-%d)
d_file="ri_recommendations_$(date +%s).csv"
d_ds="bmc2_aws"
 

read -rep "AWS Account ID (default $d_account_id): " account_id
read -rep "Start Date (default $d_start): " start
read -rep "End Date (default $d_end): " end
read -rep "Dataset (default $d_ds): " ds
read -rep "Output File (default $d_file): " file

cat <<EOF > ri_query.txt
WITH usage AS (
  SELECT 
    count(cc.ts) as num_instances_in_hour,
    sum(cc.v) as cost_in_hour,
    k.instance_type,
    k.region,
    k.operating_system,
    k.operation,
    k.account_id,
    REGEXP_REPLACE(k.description, r'"\\\$[0-9]*(\.[0-9]*)? ', '') as description,
    REGEXP_EXTRACT(k.description, r'Dedicated') = "Dedicated" as dedicated,
    ROW_NUMBER() OVER(PARTITION BY k.instance_type, k.region, k.operating_system, REGEXP_REPLACE(k.description, r'"\\\$[0-9]*(\.[0-9]*)? ', '') ORDER BY count(cc.ts) desc) as row_number
  FROM sap_aws.keys k
  INNER JOIN sap_aws.cost c ON c.key = k.key,
    unnest(c.cost) as cc
  WHERE k.instance_type is not null 
    and k.category = "compute" 
    and k.usage_type = "BoxUsage" 
    and (DATE(c._PARTITIONTIME) BETWEEN DATE("$d_start") AND DATE("$d_end"))  -- change dates as needed, also in WHERE clause for pricing
    and c.amortized_unblended is true
    and k.account_id = "$d_account_id"
  --  and operating_system = "Windows"
  --  and instance_type = 'r3.8xlarge' and region = "US East (N. Virginia)" and operating_system = "SUSE"
  --  and instance_type = 'm4.4xlarge' and region = "US West (Oregon)"      and operating_system = "Linux"
  --  and instance_type = 't2.medium'   and region = "US East (N. Virginia)" and operating_system = "Linux"
  --  and instance_type = 'm4.large'   and region = "US East (N. Virginia)" and operating_system = "Linux"
  GROUP BY 
    cc.ts,
    k.instance_type,
    k.region,
    k.operating_system,
    k.description,
    k.operation,
    k.account_id
  ORDER BY 
    num_instances_in_hour desc,
    row_number asc
),
pricing as (
  SELECT 
    rip.RateCode,
    pod.RateCode as PodRateCode,
    rip.Tenancy,
    pod.Tenancy podTenancy,
    usage.description,
    usage.row_number,
    usage.num_instances_in_hour as ris_to_purchase,
    usage.instance_type,
    usage.region,
    usage.operating_system,
    rip.PricePerUnit/(3*8760) * 0.75 as ri_rate, -- this needs to changed based on RI duration, also in the WHERE clause
    pod.PricePerUnit * 0.85 as on_demand_rate
  FROM  usage
  INNER JOIN sap_dev_aws.pricing rip 
    ON  rip.Instance_Type = usage.instance_type 
    AND rip.Location = usage.region 
    AND rip.Operating_System = usage.operating_system 
    AND rip.Tenancy=IF(usage.dedicated, "Dedicated", "Shared") 
    AND rip.TermType = "Reserved" 
    AND rip.LeaseContractLength="3yr" 
    AND rip.PurchaseOption="All Upfront" 
    AND rip.OfferingClass = "standard" 
    AND rip.Unit="Quantity" 
    AND rip.Operation = usage.operation
  INNER JOIN sap_dev_aws.pricing pod 
    ON  pod.Instance_Type = rip.instance_type 
    AND pod.Location = rip.Location 
    AND pod.Operating_System = rip.operating_system 
    AND pod.Tenancy=IF(usage.dedicated, "Dedicated", "Shared") 
    AND pod.TermType = "OnDemand" 
    AND pod.Operation = usage.operation
  WHERE 
    usage.row_number = CAST(FLOOR(TIMESTAMP_DIFF(CAST(DATE("$d_end") AS TIMESTAMP), CAST(DATE("$d_start") AS TIMESTAMP), HOUR)  * ((rip.PricePerUnit*0.75/(3*8760))/pod.PricePerUnit*0.85)) AS int64)
)

SELECT 
  usage.account_id,
  ris_to_purchase,
  usage.instance_type,
  usage.region,
  usage.operating_system,
  IF(usage.dedicated, "Dedicated", "Shared") as tenancy,
  pricing.on_demand_rate,
  pricing.ri_rate,
  SUM(cost_in_hour) as no_new_ri_costs,
  SUM(cost_in_hour-(ris_to_purchase*on_demand_rate)+ ris_to_purchase*ri_rate) as with_new_ri_costs,
  SUM(cost_in_hour) - SUM(cost_in_hour-(ris_to_purchase*on_demand_rate)+ ris_to_purchase*ri_rate) savings,
  100 - 100 * SUM(cost_in_hour-(ris_to_purchase*on_demand_rate)+ ris_to_purchase*ri_rate) / SUM(cost_in_hour) savings_percentage
FROM usage 
INNER JOIN pricing 
  ON usage.instance_type = pricing.instance_type 
  AND usage.region=pricing.region 
  AND usage.operating_system=pricing.operating_system 
  AND usage.description=pricing.description
GROUP BY 
  usage.account_id,
  ris_to_purchase,
  usage.instance_type,
  usage.region,
  usage.operating_system,
  usage.description,
  usage.dedicated,
  pricing.on_demand_rate,
  pricing.ri_rate
ORDER BY usage.account_id, savings DESC

EOF

bq --format=csv --project_id="optima-tve" query --nouse_legacy_sql --max_rows="1000000000" "$(< ri_query.txt)" | sed '/^$/d' > "./${file:=$d_file}"

echo
echo "Saved ${file:=$d_file}"
