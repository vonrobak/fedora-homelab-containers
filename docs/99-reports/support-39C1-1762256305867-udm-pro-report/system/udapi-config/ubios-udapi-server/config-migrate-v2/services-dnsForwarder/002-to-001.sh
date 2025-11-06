#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/dnsForwarder"=1'

# no need to downgrade from 002 to 001 if no ipsets
JQT "${1}" '."services.dnsForwarder".ipsets[]?' && exit 0

# Facts about config parsing in `dnsmasq`:
#  1) `dnsmasq` can handle lines up to 1024 bytes when parsing config file
#  2) If line length is greater than 1024 bytes then `dnsmasq` fails to start
#  3) In version 002 `uus` splits lines longer that 1024 to smaller ones and `dnsmasq` starts successfully
#  4) But in older version 001 `uus` tries to feed long config lines to `dnsmasq` and it crashes
#  
# Summary - when downgrading from 002 to 001 we should remove hosts that exceed total 
#           length of 1024 bytes 

# Maximum line length of dnsmasq config file 
line_limit=1000

# Size of constants to be used when calculating length of config line
ipset_len=`expr length "ipset"`
ubiosx_len=`expr length "UBIOSX"`

# Walk ".services.dnsForwarder.ipsets[]" array
ipset_num=`jq -r ".services.dnsForwarder.ipsets | length" ${1}`
i=0; while [ $i -lt $ipset_num ]; do
    ipsets_path=".services.dnsForwarder.ipsets[$i]"
    i=$(($i + 1)) # Next ipset

    # Get size of .services.dnsForwarder.ipsets[] array
    host_num=`jq -r "$ipsets_path.hosts | length" ${1}`
    [ $host_num -eq 0 ] && continue

    # Get number of ipset names
    ipsets_names_num=`jq -r "$ipsets_path.ipsets | length" ${1}`

    # Build comma-separated string containing ipset names
    ipsets_names=`jq -r "$ipsets_path.ipsets | map(.) | join(\",\")" ${1}`
    ipsets_names_len=${#ipsets_names}

    # Get length ipset prefix&suffix calculated from ipset names that looks looks so:
    #     "ipset=/UBISO4ipset_name1,UBISO6ipset_name1,UBISO4ipset_name2,UBISO6ipset_name2"
    reserved_len=$((1 + $ipsets_names_len * 2 + $ubiosx_len * $ipsets_names_num * 2))
    line_max_len=$(($line_limit - $reserved_len))

    # Walk ".services.dnsForwarder.ipsets[].hosts[]" array
    # and trim entries that exceed line limit 
    hosts_len=0
    j=0; while [ $j -lt $host_num ]; do
        hosts_path="$ipsets_path.hosts[$j]"
        host=`jq -r "$hosts_path" ${1}`
        host_len=${#host}
        hosts_len=$(($hosts_len + $host_len + 1))

        # Delete hosts that exceeds limit (or even full ipset, if no hosts could be added).
        if [ $hosts_len -gt $line_max_len ]; then
            if [ $j -eq 0 ]; then
                echo "Deleting ipset $ipsets_path"
                JQA "${1}" ". | del($ipsets_path)"

                # Backpedal current index and number of ipsets
                i=$(($i - 1))
                ipset_num=$(($ipset_num - 1))
            else
                echo "Deleting hosts $ipsets_path.hosts[$j:]"
                JQA "${1}" ". | del($ipsets_path.hosts[$j:])"
            fi
            break
        fi
        j=$((j + 1)) # Next host
    done
done

exit 0
