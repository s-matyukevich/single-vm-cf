#!/bin/bash

set -ef -o pipefail

if [ -n "${CF_DEPLOYMENT_TRACE}" ]; then
  set -x
fi

set -u

# Check for spiff installation
which spiff > /dev/null 2>&1 || {
  echo "Aborted. Please install spiff by following https://github.com/cloudfoundry-incubator/spiff#installation" 1>&2
  exit 1
}

root_dir=$(cd "$(dirname "$0")/.." && pwd)

templates="${root_dir}/templates"
cf_templates="${root_dir}/cf-release/templates"


spiff merge \
  "${cf_templates}/generic-manifest-mask.yml" \
  "${templates}/jobs-single-vm-aws.yml" \
  "${cf_templates}/cf.yml" \
  "${templates}/infrastructure-single-vm-aws.yml" \
  "$@"
