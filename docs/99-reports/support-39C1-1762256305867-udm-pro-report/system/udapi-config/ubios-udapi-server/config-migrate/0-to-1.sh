#!/bin/sh
cat ${1} | jq '. |= { "version": 1 } + .' > ${1}.tmp && mv ${1}.tmp ${1}
