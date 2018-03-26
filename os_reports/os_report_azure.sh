#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

d_start=$(date -v-32d +%Y-%m-%d)
d_end=$(date -v-2d +%Y-%m-%d)
d_file="os_report_$(date +%s).csv"
d_ds="bat_azure"

read -rep "Start Date (default $d_start): " start
read -rep "End Date (default $d_end): " end
read -rep "Dataset (default $d_ds): " ds
read -rep "Output File (default $d_file): " file

read -r -d '\0' query << EOF
WITH data AS ( SELECT format_timestamp("%x %R", d.ts) date, sum(d.cost) * 24 * 30.5 cost,
IFNULL(k.operating_system,'-none-') operating_system, IFNULL(k.service_info_2,'-none-') os_detail, IFNULL(k.resource_id,'-none-') resource_id
FROM \`optima-tve.${ds:=$d_ds}.keys\` AS k LEFT JOIN \`optima-tve.${ds:=$d_ds}.cost\` AS d ON k.key = d.key
WHERE (d._PARTITIONTIME BETWEEN timestamp("${start:=$d_start}T23:00:00.000Z") AND timestamp("${end:=$d_end}T23:00:00.000Z"))
and (resource_type like 'Virtual Machines%') and (service = 'Microsoft.Compute')
GROUP BY date, operating_system, os_detail, resource_id)
select distinct resource_id, operating_system, os_detail from data\0
EOF

bq --format=csv --project_id="optima-tve" query --nouse_legacy_sql --max_rows="1000000000" <<< "$query" | sed '/^$/d' > "./${file:=$d_file}"

echo
echo "Saved ${file:=$d_file}"
