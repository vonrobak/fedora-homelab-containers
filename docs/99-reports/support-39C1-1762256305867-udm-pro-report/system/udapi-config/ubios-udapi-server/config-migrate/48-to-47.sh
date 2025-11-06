#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=47'

# get all features and sort them in reverse order
CONFIG_MIGRATE_V2_DIR="$(dirname "${0}")"/../config-migrate-v2
CONFIG_MIGRATE_V2_ORDER_FILE="${CONFIG_MIGRATE_V2_DIR}/migration-order.json"
if [ -f "${CONFIG_MIGRATE_V2_ORDER_FILE}" ]
then
    FEATURES_LIST=$(cat "${CONFIG_MIGRATE_V2_ORDER_FILE}" | jq -r '. | reverse | .[]?')
fi

# check if any features used in config are missing
EXTRA_FEATURES_LIST=$(cat "${1}" | jq -r '.versionDetail // {} | key<FILTERED> | .[]?')
for feature in ${EXTRA_FEATURES_LIST}
do
    if $(echo "${FEATURES_LIST}" | grep -qv "${feature}")
    then
        FEATURES_LIST="${feature} ${FEATURES_LIST}"
    fi
done

# go through features stored in reverse order and execute .versionFormat: "v2" downgrade scripts
for feature in ${FEATURES_LIST}
do
    # find feature information
    feature_dir="$(echo -n "${feature}"|tr -c '[:alnum:]' '-')"
    cfg_feature_version="$(cat "${1}" | jq -r '.versionDetail."'${feature}'" // 0')"
    # execute scripts one by one
    while [ ${cfg_feature_version} -gt 0 ]
    do
        cfg_next_feature_version=$(expr ${cfg_feature_version} - 1)
        script_path="${feature_dir}/$(printf "%03d-to-%03d.sh" ${cfg_feature_version} ${cfg_next_feature_version})"
        script_full_path="${CONFIG_MIGRATE_V2_DIR}/${script_path}"
        echo "downgrading ${feature} from ${cfg_feature_version} to ${cfg_next_feature_version} -- executing ${script_path}"
        if [ -f "${script_full_path}" ]
        then
            ${script_full_path} ${1}
            result=${?}
            [ ${result} -ne 0 ] && echo "Error (${result}) executing ${script_path}"
        else
            echo "Error (no script) executing ${script_path}"
        fi
        cfg_feature_version=${cfg_next_feature_version}
    done
done

# cleanup attributes
JQA "${1}" 'del(.versionFormat) | del(.versionDetail)'

exit 0
