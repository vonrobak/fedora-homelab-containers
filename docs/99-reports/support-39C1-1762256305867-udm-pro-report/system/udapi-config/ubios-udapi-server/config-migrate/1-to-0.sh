#!/bin/sh
cat ${1} | jq 'del(.version)' > ${1}.tmp && mv ${1}.tmp ${1}
