#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."firewall/filter"=3'

# Get the number of filters
filter_len=$(jq -r '."firewall/filter" | length' "${1}")

# Iterate over each filter
for i in $(seq 0 `expr $filter_len - 1`)
do
	# Get the rules array for the current filter
	rules=$(jq -r --argjson i "$i" '."firewall/filter"[$i].rules' "${1}")
	# Get the number of rules
	rules_len=$(echo "$rules" | jq -r 'length')


	if [ "$rules_len" -gt "0" ]; then
		newrules=[]

		# Iterate over each rule
		for j in $(seq 0 `expr $rules_len - 1`)
		do
			# Get the apps array for the current rule
			apps=$(echo "$rules" | jq -r --argjson j "$j" '.[$j].apps')
			# Get the number of apps
			apps_len=$(echo "$apps" | jq -r 'length')

			# Split each app object in the rules array
			if [ "$apps_len" -gt "0" ]; then
				for k in $(seq 0 `expr $apps_len - 1`)
				do
					app=$(echo "$apps" | jq -r --argjson k "$k" '.[$k]')
					newrule=$(echo "$rules" | jq -r --argjson j "$j" --argjson app "$app" \
						'(.[$j] += $app) | (.[$j] | del(.apps, .id))')
					newrules=$(echo "$newrules" | jq -r --argjson newrule "$newrule" '. += [$newrule]')
				done
			else
				newrule=$(echo "$rules" | jq -r --argjson j "$j" '.[$j]')
				newrules=$(echo "$newrules" | jq -r --argjson newrule "$newrule" '. += [$newrule]')
			fi
		done

		# Update the rules in the original JSON file
		jq  --indent 1 --argjson i "$i" --argjson newrules "$newrules" '."firewall/filter"[$i].rules = $newrules' "${1}"  > /tmp/tmp_udapi-firewall-filter-004-to-003.json && mv /tmp/tmp_udapi-firewall-filter-004-to-003.json "${1}"
	fi
done

exit 0
