#!/usr/bin/env bash
# Runs at startup, before kea-dhcp4. Republishes the still-valid leases from
# Kea's memfile lease files to Kafka, then tombstones the leases in the topic
# that have expired.
set -eo pipefail

kcat_produce=(kcat -b "${KAFKA_BOOTSTRAP_SERVER}" -t "${KAFKA_TOPIC_NAME}" -P -K: -zzstd
  # Give up on a message after 30s rather than the default 5 minutes, so an
  # unreachable broker doesn't hold up DHCP for long.
  -X message.timeout.ms=30000)

# The lease files, oldest first, the way Kea loads them: lease file cleanup
# (LFC) leaves either a merged <file>.completed or the older <file>.2 and
# <file>.1, and <file> holds the newest records.
shopt -s nullglob
lease_files=()
for leasefile in /kea/*.csv; do
    if [ -e "${leasefile}.completed" ]; then
        lease_files+=("${leasefile}.completed")
    else
        for old in "${leasefile}.2" "${leasefile}.1"; do
            [ -e "${old}" ] && lease_files+=("${old}")
        done
    fi
    lease_files+=("${leasefile}")
done
shopt -u nullglob

if [ ${#lease_files[@]} -gt 0 ]; then
    echo "Replacing leases with valid ones from lease files: ${lease_files[*]}"
    # Lease file columns: 1 address, 2 hwaddr, 4 valid_lifetime, 5 expire,
    # 10 state. A lease can appear many times; the record with the latest
    # client last transaction time (cltt = expire - valid_lifetime) is its
    # current state, and on a tie the later record wins. Kea marks a deleted
    # lease with a record whose valid_lifetime is 0, so it never counts as
    # valid.
    awk -F, -v now="$(date +%s)" '
        BEGIN { now += 0 }
        FNR == 1 { next }  # header
        {
            mac = $2; gsub(":", "", mac)
            if (mac == "") next
            cltt = $5 - $4
            if (!(mac in best) || cltt >= best[mac]) {
                best[mac] = cltt; lft[mac] = $4 + 0; expire[mac] = $5 + 0
                ip[mac] = $1; state[mac] = $10 + 0
            }
        }
        END {
            for (mac in best) {
                # state 0 is an active lease (an empty column counts as 0)
                if (expire[mac] > now && state[mac] == 0)
                    printf "%s:{\"timestamp\":%d,\"valid_lifetime\":%d,\"mac\":\"%s\",\"ip\":\"%s\"}\n", mac, best[mac], lft[mac], mac, ip[mac]
            }
        }' "${lease_files[@]}" \
      | tee /dev/stderr \
      | "${kcat_produce[@]}"
fi

echo "Removing expired leases"
# The last message per key is the lease's current state; a null payload is a
# tombstone. -n so that inputs reads every message, the first one included.
expired_leases=$(kcat -b "${KAFKA_BOOTSTRAP_SERVER}" -t "${KAFKA_TOPIC_NAME}" -e -C -J \
  | jq -n -r 'reduce inputs as $line ({}; . + {($line.key): $line.payload})
    | to_entries
    | .[]
    | select(.value!=null)
    | .value' \
  | jq -r --argjson curtime "$(date +'%s')" '.
    | select((.timestamp + .valid_lifetime) <= $curtime)
    | .mac')

for mac in $expired_leases; do
    echo "Removing expired lease for mac: ${mac}"
    echo -n "${mac}:" | "${kcat_produce[@]}" -Z
done
