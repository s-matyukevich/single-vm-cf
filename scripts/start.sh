#!/bin/bash

set -e

if [[ -z $1 ]]; then
    >&2 echo "Usage:"
    >&2 echo -e "\t$0 <domain>"
    exit 1
fi

domain=$1

rm /var/vcap/data -rf
mv /var/vcap/data_copy /var/vcap/data
ln -s /etc/sv/monit /etc/service

# Replace the old system domain / IP with the new system domain / IP

config_files=$(find /var/vcap/jobs/*/ /var/vcap/monit/job -type f)

ip=$(ip route get 1 | awk '{print $NF;exit}')
old_ip='private_ip_placeholder'
perl -p -i -e "s/\\Q$old_ip\\E/$ip/g" $config_files
echo "Setting private ip to $ip"

old_domain='domain_placeholder'
perl -p -i -e "s/\\Q$old_domain\\E/$domain/g" $config_files
echo "Setting system domain to $domain"

monit="/var/vcap/bosh/bin/monit"
monit_summary() { while output=$($monit summary 2>&1) && [[ $output = *"error connecting to the monit daemon"* ]]; do sleep 1; done; echo "$output"; }
total_services() { monit_summary | grep -E '^(Process|File|System)' | wc -l; }
started_service_count() { started_services | wc -l; }
started_services() { monit_summary | grep -E '(running|accessible|Timestamp changed|PID changed)' | awk '{print $2}' | tr -d "'"; }
stopped_services() { monit_summary | grep 'not monitored' | grep -v 'pending' | awk '{print $2}' | tr -d "'"; }
wait_for_monit_to_start() { while [[ $(total_services) = 0 ]]; do sleep 1; done; }
cc_status_code() { curl -s -I -o /dev/null -w %{http_code} -H "Host: api.$1" http://localhost/v2/info; }

for script in /var/vcap/jobs/*/bin/pre-start; do
  $script
done

echo "Waiting for services to start..."

sv start monit
wait_for_monit_to_start

start_services() {
  for service in $@; do
    $monit start $service
  done

  for service in $@; do
    while ! monit_summary | grep $service | grep -q running; do sleep 1; done;
  done
}


start_remaining() { 
  for service in $(stopped_services); do
    $monit start $service
  done
}


start_services postgres

start_remaining
total=$(total_services)

while started=$(started_service_count) && [[ $started -lt $total ]]; do
  counter=$(($counter + 1))
  [[ $(($counter % 60)) = 0 ]] && echo "$started out of $total running"
  sleep 1
done

echo "$total out of $total running"

for script in /var/vcap/jobs/*/bin/post-start; do
  $script
done

while [[ $(cc_status_code "$domain") != 200 ]]; do
  sleep 1
done
