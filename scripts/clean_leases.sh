#!/usr/bin/env bash
set -eo pipefail

echo "Replacing leases with valid ones from lease file"
# This will break without these settings
shopt -s nullglob dotglob
curdate=$(date +'%s')
for leasefile in /kea/*.csv*; do
    echo "Reading lease file ${leasefile} for valid leases"
    tail -n +2 <"$leasefile" | \
    awk -F , '{print $2,$4,$5,$1}' | \
    while read -r mac expiration valid_lifetime ip; do
        if (( curdate - expiration <= valid_lifetime )); then
            event_timestamp=$((valid_lifetime - expiration))
            mac=$(echo "${mac}" | tr -d ':')
            msg="{\"timestamp\":${event_timestamp},\"valid_lifetime\":${expiration},\"mac\":\"${mac}\",\"ip\":\"${ip}\"}"
            echo "Sending kafka message topic: ${KAFKA_TOPIC_NAME} key: ${mac} value: ${msg}"
            echo -n "${mac}:${msg}" | kcat -b "${KAFKA_BOOTSTRAP_SERVER}" -t "${KAFKA_TOPIC_NAME}" -K: -P -zzstd
        fi
    done
done
shopt -u nullglob dotglob

echo "Removing expired leases"
expired_leases=$(kcat -b "${KAFKA_BOOTSTRAP_SERVER}" -t "${KAFKA_TOPIC_NAME}" -e -C -J \
  | jq -r 'reduce inputs as $line ({}; . + {($line.key): $line.payload})
    | to_entries
    | .[]
    | select(.value!=null)
    | .value' \
  | jq -r --argjson curtime "$(date +'%s')" '.
    | select((.timestamp + .valid_lifetime) <= $curtime)
    | .mac')

for mac in $expired_leases; do
    echo "Removing expired lease for mac: ${mac}"
    echo -n "${mac}:" | kcat -b "${KAFKA_BOOTSTRAP_SERVER}" -t "${KAFKA_TOPIC_NAME}" -P -K: -Z -zzstd
done