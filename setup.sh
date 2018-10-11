#!/bin/bash -e

#
# $1 -- optional argument specifying a sleep period between provisioning
#       node2 and node1

# TODO: rewrite this using fabric once
# https://github.com/fabric/fabric/issues/1888 and
# https://github.com/paramiko/paramiko/issues/1316 are fixed.

. ./bashvagsible.sh

if ! test -f "cfengine-nova-hub-3.12.0-1.x86_64.rpm"; then
    wget "https://cfengine-package-repos.s3.amazonaws.com/enterprise/Enterprise-3.12.0/hub/redhat_6_x86_64/cfengine-nova-hub-3.12.0-1.x86_64.rpm"
fi
if ! test -f "cfengine-nova-3.12.0-1.el6.x86_64.rpm"; then
    wget "https://cfengine-package-repos.s3.amazonaws.com/enterprise/Enterprise-3.12.0/agent/agent_rhel6_x86_64/cfengine-nova-3.12.0-1.el6.x86_64.rpm"
fi

function vagrant_cluster_up() {
    # $1 -- optional argument specifying a sleep period between provisioning
    #       node2 and node1
    set -x
    vagrant up --provider=libvirt --no-provision node{1,2}
    vagrant provision node2
    if [ $# -gt 0 ]; then
        sleep $1;
    fi
    vagrant provision node1
    set +x
}

function first() {
    echo $1
}

function second() {
    echo $2
}

echo "Getting the sudo cookie"
sudo echo "Thanks! Now let's hope it won't timeout too soon."

# just in case there was a previous setup running
vagrant destroy

sleep_period=""
if [ $# -gt 0 ]; then
    sleep_period=$1
fi
vagrant_cluster_up $sleep_period

nodes=`get_nodes`
first_node=`first $nodes`
second_node=`second $nodes`

run_on $first_node  'pushd /tmp; su cfpostgres -c "/var/cfengine/bin/pg_ctl -w -D /var/cfengine/state/pg/data -l /var/log/postgresql.log start"; popd'
run_on $second_node 'rm -rf /var/cfengine/state/pg/data/*'
run_on $second_node 'pushd /tmp; su cfpostgres -c "cd /tmp && /var/cfengine/bin/pg_basebackup -h node1-pg -U cfpostgres -D /var/cfengine/state/pg/data -X stream -P"; popd'
run_on $second_node 'cp /vagrant/recovery.conf /var/cfengine/state/pg/data/recovery.conf'
run_on $second_node 'chown --reference /var/cfengine/state/pg/data/postgresql.conf /var/cfengine/state/pg/data/recovery.conf'

run_on $second_node 'pushd /tmp; su cfpostgres -c "/var/cfengine/bin/pg_ctl -D /var/cfengine/state/pg/data -l /var/log/postgresql.log start"; popd'
run_on $second_node '/var/cfengine/bin/psql -x cfdb -c "SELECT pg_is_in_recovery();"'
run_on $first_node  '/var/cfengine/bin/psql -x cfdb -c "SELECT * FROM pg_stat_replication;"'

run_all_parallel 'pushd /tmp; su cfpostgres -c "/var/cfengine/bin/pg_ctl -D /var/cfengine/state/pg/data -l /var/log/postgresql.log stop"; popd'

run_on $first_node 'pcs resource create cfpgsql pgsql  \
  pgctl="/var/cfengine/bin/pg_ctl" \
  psql="/var/cfengine/bin/psql"    \
  pgdata="/var/cfengine/state/pg/data" \
  pgdb="cfdb" pgdba="cfpostgres" repuser="cfpostgres" \
  tmpdir="/var/cfengine/state/pg/tmp" \
  rep_mode="async" node_list="node1 node2" \
  primary_conninfo_opt="keepalives_idle=60 keepalives_interval=5 keepalives_count=5" \
  master_ip="192.168.130.100" restart_on_promote="true" \
  logfile="/var/log/postgresql.log" \
  config="/var/cfengine/state/pg/data/postgresql.conf" \
  check_wal_receiver=true restore_command="cp /var/cfengine/state/pg/data/pg_arch/%f %p" \
  op monitor timeout="60s" interval="3s" on-fail="restart" role="Master" \
  op monitor timeout="60s" interval="4s" on-fail="restart" --disable'

run_on $first_node 'pcs resource master mscfpgsql cfpgsql master-max=1 master-node-max=1 clone-max=2 clone-node-max=1 notify=true'
run_on $first_node 'pcs constraint colocation add cfengine with Master mscfpgsql INFINITY'
run_on $first_node 'pcs constraint order promote mscfpgsql then start cfengine symmetrical=false score=INFINITY'
run_on $first_node 'pcs constraint order demote mscfpgsql then stop cfengine symmetrical=false score=0'
run_on $first_node 'pcs constraint location mscfpgsql prefers node1'
run_on $first_node 'pcs resource enable mscfpgsql --wait=30'

sleep 1m
run_on $first_node 'crm_mon -Afr1'

status=`run_on_silent $second_node 'crm_mon -Afr1'`
echo "$status"
lines=`echo "$status" | sed -r -e '/(Masters|Slaves): \[/!d' | wc -l`
test $lines -eq 2               # one master, one slave

run_all_serial '/var/cfengine/bin/cf-agent --bootstrap node1-pg'
run_on $second_node '/var/cfengine/bin/cf-agent --bootstrap node2-pg'

cf_key_s=`run_on_silent $second_node '/var/cfengine/bin/cf-key -s'`
first_key=` echo "$cf_key_s" | sed -r -e '/192\.168\.130\.10/!d' -e 's/^.*SHA=([a-z0-9]+).*/\1/' | sort | uniq`
second_key=`echo "$cf_key_s" | sed -r -e '/192\.168\.130\.11/!d' -e 's/^.*SHA=([a-z0-9]+).*/\1/' | sort | uniq`

run_all_parallel 'cp /vagrant/ha_info.json.template /var/cfengine/masterfiles/cfe_internal/enterprise/ha/ha_info.json'
run_all_parallel "sed -ri s/@NODE1_PKSHA@/$first_key/ /var/cfengine/masterfiles/cfe_internal/enterprise/ha/ha_info.json"
run_all_parallel "sed -ri s/@NODE2_PKSHA@/$second_key/ /var/cfengine/masterfiles/cfe_internal/enterprise/ha/ha_info.json"
run_on $first_node 'cat /var/cfengine/masterfiles/cfe_internal/enterprise/ha/ha_info.json'

run_all_parallel 'sed -ri -e "/\s+\"enable_cfengine_enterprise_hub_ha\" expression/d" -e "s/#\"enable_cfengine_enterprise_hub_ha\"/\"enable_cfengine_enterprise_hub_ha\"/" /var/cfengine/masterfiles/controls/def.cf'

run_all_parallel '/var/cfengine/bin/cf-agent -Kf update.cf'
run_all_parallel 'service cfengine3 restart'

vagrant up --provider=libvirt node3

echo "Done! Go ahead and try logging in at https://192.168.130.100"
