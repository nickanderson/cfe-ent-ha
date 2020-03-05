#!/bin/sh
#
# Description:  Manages a PostgreSQL Server as an OCF High-Availability
#               resource
#
# Authors:      Serge Dubrouski (sergeyfd@gmail.com) -- original RA
#               Florian Haas (florian@linbit.com) -- makeover
#               Takatoshi MATSUO (matsuo.tak@gmail.com) -- support replication
#               David Corlette (dcorlette@netiq.com) -- add support for non-standard library locations and non-standard port
#
# Copyright:    2006-2012 Serge Dubrouski <sergeyfd@gmail.com>
#                         and other Linux-HA contributors
# License:      GNU General Public License (GPL)
#
###############################################################################
# Initialization:

: ${OCF_FUNCTIONS_DIR=${OCF_ROOT}/lib/heartbeat}
. ${OCF_FUNCTIONS_DIR}/ocf-shellfuncs

# Use runuser if available for SELinux.
if [ -x /sbin/runuser ]; then
    SU=runuser
else
    SU=su
fi

#
# Get PostgreSQL Configuration parameter
#
get_pgsql_param() {
    local param_name

    param_name=$1
    perl_code="if (/^\s*$param_name[\s=]+\s*(.*)$/) {
       \$dir=\$1;
       \$dir =~ s/\s*\#.*//;
       \$dir =~ s/^'(\S*)'/\$1/;
       print \$dir;}"

    perl -ne "$perl_code" < $OCF_RESKEY_config
}

# Defaults
OCF_RESKEY_pgctl_default=/usr/bin/pg_ctl
OCF_RESKEY_psql_default=/usr/bin/psql
OCF_RESKEY_pgdata_default=/var/lib/pgsql/data
OCF_RESKEY_pgdba_default=postgres
OCF_RESKEY_pghost_default=""
OCF_RESKEY_pgport_default=5432
OCF_RESKEY_pglibs_default=/usr/lib
OCF_RESKEY_start_opt_default=""
OCF_RESKEY_ctl_opt_default=""
OCF_RESKEY_pgdb_default=template1
OCF_RESKEY_logfile_default=/dev/null
OCF_RESKEY_stop_escalate_default=90
OCF_RESKEY_monitor_user_default=""
OCF_RESKEY_monitor_password_default=""
OCF_RESKEY_monitor_sql_default="select now();"
OCF_RESKEY_check_wal_receiver_default="false"
# Defaults for replication
OCF_RESKEY_rep_mode_default=none
OCF_RESKEY_node_list_default=""
OCF_RESKEY_restore_command_default=""
OCF_RESKEY_archive_cleanup_command_default=""
OCF_RESKEY_recovery_end_command_default=""
OCF_RESKEY_master_ip_default=""
OCF_RESKEY_repuser_default="postgres"
OCF_RESKEY_primary_conninfo_opt_default=""
OCF_RESKEY_restart_on_promote_default="false"
OCF_RESKEY_tmpdir_default="/var/lib/pgsql/tmp"
OCF_RESKEY_xlog_check_count_default="3"
OCF_RESKEY_crm_attr_timeout_default="5"
OCF_RESKEY_stop_escalate_in_slave_default=90
OCF_RESKEY_replication_slot_name_default=""

: ${OCF_RESKEY_pgctl=${OCF_RESKEY_pgctl_default}}
: ${OCF_RESKEY_psql=${OCF_RESKEY_psql_default}}
: ${OCF_RESKEY_pgdata=${OCF_RESKEY_pgdata_default}}
: ${OCF_RESKEY_pgdba=${OCF_RESKEY_pgdba_default}}
: ${OCF_RESKEY_pghost=${OCF_RESKEY_pghost_default}}
: ${OCF_RESKEY_pgport=${OCF_RESKEY_pgport_default}}
: ${OCF_RESKEY_pglibs=${OCF_RESKEY_pglibs_default}}
: ${OCF_RESKEY_config=${OCF_RESKEY_pgdata}/postgresql.conf}
: ${OCF_RESKEY_start_opt=${OCF_RESKEY_start_opt_default}}
: ${OCF_RESKEY_ctl_opt=${OCF_RESKEY_ctl_opt_default}}
: ${OCF_RESKEY_pgdb=${OCF_RESKEY_pgdb_default}}
: ${OCF_RESKEY_logfile=${OCF_RESKEY_logfile_default}}
: ${OCF_RESKEY_stop_escalate=${OCF_RESKEY_stop_escalate_default}}
: ${OCF_RESKEY_monitor_user=${OCF_RESKEY_monitor_user_default}}
: ${OCF_RESKEY_monitor_password=${OCF_RESKEY_monitor_password_default}}
: ${OCF_RESKEY_monitor_sql=${OCF_RESKEY_monitor_sql_default}}
: ${OCF_RESKEY_check_wal_receiver=${OCF_RESKEY_check_wal_receiver_default}}

# for replication
: ${OCF_RESKEY_rep_mode=${OCF_RESKEY_rep_mode_default}}
: ${OCF_RESKEY_node_list=${OCF_RESKEY_node_list_default}}
: ${OCF_RESKEY_restore_command=${OCF_RESKEY_restore_command_default}}
: ${OCF_RESKEY_archive_cleanup_command=${OCF_RESKEY_archive_cleanup_command_default}}
: ${OCF_RESKEY_recovery_end_command=${OCF_RESKEY_recovery_end_command_default}}
: ${OCF_RESKEY_master_ip=${OCF_RESKEY_master_ip_default}}
: ${OCF_RESKEY_repuser=${OCF_RESKEY_repuser_default}}
: ${OCF_RESKEY_primary_conninfo_opt=${OCF_RESKEY_primary_conninfo_opt_default}}
: ${OCF_RESKEY_restart_on_promote=${OCF_RESKEY_restart_on_promote_default}}
: ${OCF_RESKEY_tmpdir=${OCF_RESKEY_tmpdir_default}}
: ${OCF_RESKEY_xlog_check_count=${OCF_RESKEY_xlog_check_count_default}}
: ${OCF_RESKEY_crm_attr_timeout=${OCF_RESKEY_crm_attr_timeout_default}}
: ${OCF_RESKEY_stop_escalate_in_slave=${OCF_RESKEY_stop_escalate_in_slave_default}}
: ${OCF_RESKEY_replication_slot_name=${OCF_RESKEY_replication_slot_name_default}}

usage() {
    cat <<EOF
        usage: $0 start|stop|status|monitor|promote|demote|notify|meta-data|validate-all|methods

        $0 manages a PostgreSQL Server as an HA resource.

        The 'start' operation starts the PostgreSQL server.
        The 'stop' operation stops the PostgreSQL server.
        The 'status' operation reports whether the PostgreSQL is up.
        The 'monitor' operation reports whether the PostgreSQL is running.
        The 'promote' operation promotes the PostgreSQL server.
        The 'demote' operation demotes the PostgreSQL server.
        The 'validate-all' operation reports whether the parameters are valid.
        The 'methods' operation reports on the methods $0 supports.
EOF
  return $OCF_ERR_ARGS
}

meta_data() {
    cat <<EOF
<?xml version="1.0"?>
<!DOCTYPE resource-agent SYSTEM "ra-api-1.dtd">
<resource-agent name="pgsql">
<version>1.0</version>

<longdesc lang="en">
Resource script for PostgreSQL. It manages a PostgreSQL as an HA resource.
</longdesc>
<shortdesc lang="en">Manages a PostgreSQL database instance</shortdesc>

<parameters>
<parameter name="pgctl" unique="0" required="0">
<longdesc lang="en">
Path to pg_ctl command.
</longdesc>
<shortdesc lang="en">pgctl</shortdesc>
<content type="string" default="${OCF_RESKEY_pgctl_default}" />
</parameter>

<parameter name="start_opt" unique="0" required="0">
<longdesc lang="en">
Start options (-o start_opt in pg_ctl). "-i -p 5432" for example.
</longdesc>
<shortdesc lang="en">start_opt</shortdesc>
<content type="string" default="${OCF_RESKEY_start_opt_default}" />

</parameter>
<parameter name="ctl_opt" unique="0" required="0">
<longdesc lang="en">
Additional pg_ctl options (-w, -W etc..).
</longdesc>
<shortdesc lang="en">ctl_opt</shortdesc>
<content type="string" default="${OCF_RESKEY_ctl_opt_default}" />
</parameter>

<parameter name="psql" unique="0" required="0">
<longdesc lang="en">
Path to psql command.
</longdesc>
<shortdesc lang="en">psql</shortdesc>
<content type="string" default="${OCF_RESKEY_psql_default}" />
</parameter>

<parameter name="pgdata" unique="0" required="0">
<longdesc lang="en">
Path to PostgreSQL data directory.
</longdesc>
<shortdesc lang="en">pgdata</shortdesc>
<content type="string" default="${OCF_RESKEY_pgdata_default}" />
</parameter>

<parameter name="pgdba" unique="0" required="0">
<longdesc lang="en">
User that owns PostgreSQL.
</longdesc>
<shortdesc lang="en">pgdba</shortdesc>
<content type="string" default="${OCF_RESKEY_pgdba_default}" />
</parameter>

<parameter name="pghost" unique="0" required="0">
<longdesc lang="en">
Hostname/IP address where PostgreSQL is listening
</longdesc>
<shortdesc lang="en">pghost</shortdesc>
<content type="string" default="${OCF_RESKEY_pghost_default}" />
</parameter>

<parameter name="pgport" unique="0" required="0">
<longdesc lang="en">
Port where PostgreSQL is listening
</longdesc>
<shortdesc lang="en">pgport</shortdesc>
<content type="integer" default="${OCF_RESKEY_pgport_default}" />
</parameter>

<parameter name="pglibs" unique="0" required="0">
<longdesc lang="en">
Custom location of the Postgres libraries. If not set, the standard location
will be used.
</longdesc>
<shortdesc lang="en">pglibs</shortdesc>
<content type="string" default="${OCF_RESKEY_pglibs_default}" />
</parameter>

<parameter name="monitor_user" unique="0" required="0">
<longdesc lang="en">
PostgreSQL user that pgsql RA will user for monitor operations. If it's not set
pgdba user will be used.
</longdesc>
<shortdesc lang="en">monitor_user</shortdesc>
<content type="string" default="${OCF_RESKEY_monitor_user_default}" />
</parameter>

<parameter name="monitor_password" unique="0" required="0">
<longdesc lang="en">
Password for monitor user.
</longdesc>
<shortdesc lang="en">monitor_password</shortdesc>
<content type="string" default="${OCF_RESKEY_monitor_password_default}" />
</parameter>

<parameter name="monitor_sql" unique="0" required="0">
<longdesc lang="en">
SQL script that will be used for monitor operations.
</longdesc>
<shortdesc lang="en">monitor_sql</shortdesc>
<content type="string" default="${OCF_RESKEY_monitor_sql_default}" />
</parameter>

<parameter name="config" unique="0" required="0">
<longdesc lang="en">
Path to the PostgreSQL configuration file for the instance.
</longdesc>
<shortdesc lang="en">Configuration file</shortdesc>
<content type="string" default="${OCF_RESKEY_pgdata}/postgresql.conf" />
</parameter>

<parameter name="pgdb" unique="0" required="0">
<longdesc lang="en">
Database that will be used for monitoring.
</longdesc>
<shortdesc lang="en">pgdb</shortdesc>
<content type="string" default="${OCF_RESKEY_pgdb_default}" />
</parameter>

<parameter name="logfile" unique="0" required="0">
<longdesc lang="en">
Path to PostgreSQL server log output file.
</longdesc>
<shortdesc lang="en">logfile</shortdesc>
<content type="string" default="${OCF_RESKEY_logfile_default}" />
</parameter>

<parameter name="socketdir" unique="0" required="0">
<longdesc lang="en">
Unix socket directory for PostgreSQL.

If you use PostgreSQL 9.3 or higher and define unix_socket_directories in the postgresql.conf, then you must set socketdir to determine which directory is used for psql command.
</longdesc>
<shortdesc lang="en">socketdir</shortdesc>
<content type="string" default="" />
</parameter>

<parameter name="stop_escalate" unique="0" required="0">
<longdesc lang="en">
Number of seconds to wait for stop (using -m fast) before resorting to -m immediate
</longdesc>
<shortdesc lang="en">stop escalation</shortdesc>
<content type="integer" default="${OCF_RESKEY_stop_escalate_default}" />
</parameter>

<parameter name="rep_mode" unique="0" required="0">
<longdesc lang="en">
Replication mode may be set to "async" or "sync" or "slave".
They require PostgreSQL 9.1 or later.
Once set, "async" and "sync" require node_list, master_ip, and
restore_command parameters,as well as configuring PostgreSQL
for replication (in postgresql.conf and pg_hba.conf).

"slave" means that RA only makes recovery.conf before starting
to connect to primary which is running somewhere.
It dosen't need master/slave setting.
It requires master_ip restore_command parameters.
</longdesc>
<shortdesc lang="en">rep_mode</shortdesc>
<content type="string" default="${OCF_RESKEY_rep_mode_default}" />
</parameter>

<parameter name="node_list" unique="0" required="0">
<longdesc lang="en">
All node names. Please separate each node name with a space.
This is optional for replication. Defaults to all nodes in the cluster
</longdesc>
<shortdesc lang="en">node list</shortdesc>
<content type="string" default="${OCF_RESKEY_node_list_default}" />
</parameter>

<parameter name="restore_command" unique="0" required="0">
<longdesc lang="en">
restore_command for recovery.conf.
This is required for replication.
</longdesc>
<shortdesc lang="en">restore_command</shortdesc>
<content type="string" default="${OCF_RESKEY_restore_command_default}" />
</parameter>

<parameter name="archive_cleanup_command" unique="0" required="0">
<longdesc lang="en">
archive_cleanup_command for recovery.conf.
This is used for replication and is optional.
</longdesc>
<shortdesc lang="en">archive_cleanup_command</shortdesc>
<content type="string" default="${OCF_RESKEY_archive_cleanup_command_default}" />
</parameter>

<parameter name="recovery_end_command" unique="0" required="0">
<longdesc lang="en">
recovery_end_command for recovery.conf.
This is used for replication and is optional.
</longdesc>
<shortdesc lang="en">recovery_end_command</shortdesc>
<content type="string" default="${OCF_RESKEY_recovery_end_command_default}" />
</parameter>

<parameter name="master_ip" unique="0" required="0">
<longdesc lang="en">
Master's floating IP address to be connected from hot standby.
This parameter is used for "primary_conninfo" in recovery.conf.
This is required for replication.
</longdesc>
<shortdesc lang="en">master ip</shortdesc>
<content type="string" default="${OCF_RESKEY_master_ip_default}" />
</parameter>

<parameter name="repuser" unique="0" required="0">
<longdesc lang="en">
User used to connect to the master server.
This parameter is used for "primary_conninfo" in recovery.conf.
This is required for replication.
</longdesc>
<shortdesc lang="en">repuser</shortdesc>
<content type="string" default="${OCF_RESKEY_repuser_default}" />
</parameter>

<parameter name="primary_conninfo_opt" unique="0" required="0">
<longdesc lang="en">
primary_conninfo options of recovery.conf except host, port, user and application_name.
This is optional for replication.
</longdesc>
<shortdesc lang="en">primary_conninfo_opt</shortdesc>
<content type="string" default="${OCF_RESKEY_primary_conninfo_opt_default}" />
</parameter>

<parameter name="restart_on_promote" unique="0" required="0">
<longdesc lang="en">
If this is true, RA deletes recovery.conf and restarts PostgreSQL
on promote to keep Timeline ID. It probably makes fail-over slower.
It's recommended to set on-fail of promote up as fence.
This is optional for replication.
</longdesc>
<shortdesc lang="en">restart_on_promote</shortdesc>
<content type="boolean" default="${OCF_RESKEY_restart_on_promote_default}" />
</parameter>

<parameter name="replication_slot_name" unique="0" required="0">
<longdesc lang="en">
Set this option when using replication slots.
Can only use lower case letters, numbers and underscore for replication_slot_name.

The replication slots would be created for each node, with the name adding the node name as postfix.
For example, replication_slot_name is "sample" and 2 slaves which are "node1" and "node2" connect to
their slots, the slots names are "sample_node1" and "sample_node2".
If the node name contains a upper case letter, hyphen and dot, those characters will be converted to a lower case letter or an underscore.
For example, Node-1.example.com to node_1_example_com.

pgsql RA doesn't monitor and delete the repliation slot.
When the slave node has been disconnected in failure or the like, execute one of the following manually.
Otherwise it may eventually cause a disk full because the master node will continue to accumulate the unsent WAL.
1. recover and reconnect the slave node to the master node as soon as possible.
2. delete the slot on the master node by following psql command.
$ select pg_drop_replication_slot('replication_slot_name');
</longdesc>
<shortdesc lang="en">replication_slot_name</shortdesc>
<content type="string" default="${OCF_RESKEY_replication_slot_name_default}" />
</parameter>

<parameter name="tmpdir" unique="0" required="0">
<longdesc lang="en">
Path to temporary directory.
This is optional for replication.
</longdesc>
<shortdesc lang="en">tmpdir</shortdesc>
<content type="string" default="${OCF_RESKEY_tmpdir_default}" />
</parameter>

<parameter name="xlog_check_count" unique="0" required="0">
<longdesc lang="en">
Number of checks of xlog on monitor before promote.
This is optional for replication.

Note: For backward compatibility, the terms are unified with PostgreSQL 9.
      If you are using PostgreSQL 10 or later, replace "xlog" with "wal".
      Likewise, replacing "location" with "lsn".
</longdesc>
<shortdesc lang="en">xlog check count</shortdesc>
<content type="integer" default="${OCF_RESKEY_xlog_check_count_default}" />
</parameter>

<parameter name="crm_attr_timeout" unique="0" required="0">
<longdesc lang="en">
The timeout of crm_attribute forever update command.
Default value is 5 seconds.
This is optional for replication.
</longdesc>
<shortdesc lang="en">The timeout of crm_attribute forever update command.</shortdesc>
<content type="integer" default="${OCF_RESKEY_crm_attr_timeout_default}" />
</parameter>

<parameter name="stop_escalate_in_slave" unique="0" required="0">
<longdesc lang="en">
Number of seconds to wait for stop (using -m fast) before resorting to -m immediate
in slave state.
This is optional for replication.
</longdesc>
<shortdesc lang="en">stop escalation_in_slave</shortdesc>
<content type="integer" default="${OCF_RESKEY_stop_escalate_in_slave_default}" />
</parameter>

<parameter name="check_wal_receiver" unique="0" required="0">
<longdesc lang="en">
If this is true, RA checks wal_receiver process on monitor
and notifies its status using "(resource name)-receiver-status" attribute.
It's useful for checking whether PostgreSQL (hot standby) connects to primary.
The attribute shows status as "normal" or "normal (master)" or "ERROR".
Note that if you configure PostgreSQL as master/slave resource, then
wal receiver is not running in the master and the attribute shows status as
"normal (master)" consistently because it is normal status.
</longdesc>
<shortdesc lang="en">check_wal_receiver</shortdesc>
<content type="boolean" default="${OCF_RESKEY_check_wal_receiver_default}" />
</parameter>
</parameters>

<actions>
<action name="start" timeout="120s" />
<action name="stop" timeout="120s" />
<action name="status" timeout="60s" />
<action name="monitor" depth="0" timeout="30s" interval="30s"/>
<action name="monitor" depth="0" timeout="30s" interval="29s" role="Master" />
<action name="promote" timeout="120s" />
<action name="demote" timeout="120s" />
<action name="notify"   timeout="90s" />
<action name="meta-data" timeout="5s" />
<action name="validate-all" timeout="5s" />
<action name="methods" timeout="5s" />
</actions>
</resource-agent>
EOF
}


#
#   Run the given command in the Resource owner environment...
#
runasowner() {
    local quietrun=""
    local loglevel="-err"
    local var

    for var in 1 2
    do
        case "$1" in
            "-q")
                quietrun="-q"
                shift 1;;
            "warn"|"err")
                loglevel="-$1"
                shift 1;;
            *)
                ;;
        esac
    done

    ocf_run $quietrun $loglevel $SU $OCF_RESKEY_pgdba -c "cd $OCF_RESKEY_pgdata; $*"
}

#
#       Shell escape
#
escape_string() {
    echo "$*" | sed -e "s/'/'\\\\''/g"
}


#
# methods: What methods/operations do we support?
#

pgsql_methods() {
    cat <<EOF
    start
    stop
    status
    monitor
    promote
    demote
    notify
    methods
    meta-data
    validate-all
EOF
}


# Execulte SQL and return the result.
exec_sql() {
    local sql="$1"
    local output
    local rc

    output=`$SU $OCF_RESKEY_pgdba -c "cd $OCF_RESKEY_pgdata; \
                $OCF_RESKEY_psql $psql_options -U $OCF_RESKEY_pgdba \
                -Atc \"$sql\""`
    rc=$?

    echo $output
    return $rc
}


#pgsql_real_start: Starts PostgreSQL
pgsql_real_start() {
    local pgctl_options
    local postgres_options
    local rc

    if pgsql_status; then
        ocf_log info "PostgreSQL is already running. PID=`cat $PIDFILE`"
        if is_replication; then
            return $OCF_ERR_GENERIC
        else
            return $OCF_SUCCESS
        fi
    fi

    # Remove postmaster.pid if it exists
    rm -f $PIDFILE

    # Remove backup_label if it exists
    if [ -f $BACKUPLABEL ] && ! is_replication; then
        ocf_log info "Removing $BACKUPLABEL. The previous backup might have failed."
        rm -f $BACKUPLABEL
    fi

    # Check if we need to create a log file
    if ! check_log_file $OCF_RESKEY_logfile
    then
        ocf_log err "PostgreSQL can't write to the log file: $OCF_RESKEY_logfile"
        return $OCF_ERR_PERM
    fi

    # Check socket directory
    if [ -n "$OCF_RESKEY_socketdir" ]
    then
        check_socket_dir
    fi

    check_stat_temp_directory

    if [ "$OCF_RESKEY_rep_mode" = "slave" ]; then
        rm -f $RECOVERY_CONF
        make_recovery_conf || return $OCF_ERR_GENERIC
    fi

    # Set options passed to pg_ctl
    pgctl_options="$OCF_RESKEY_ctl_opt -D $OCF_RESKEY_pgdata -l $OCF_RESKEY_logfile"

    # Set options passed to the PostgreSQL server process
    postgres_options="-c config_file=${OCF_RESKEY_config}"

    if [ -n "$OCF_RESKEY_pghost" ]; then
        postgres_options="$postgres_options -h $OCF_RESKEY_pghost"
    fi
    if [ -n "$OCF_RESKEY_start_opt" ]; then
        postgres_options="$postgres_options $OCF_RESKEY_start_opt"
    fi

    # Tack pass-through options onto pg_ctl options
    pgctl_options="$pgctl_options -o '$postgres_options'"

    # Invoke pg_ctl
    runasowner "unset PGUSER; unset PGPASSWORD; $OCF_RESKEY_pgctl $pgctl_options -W start"

    if [ $? -eq 0 ]; then
        # Probably started.....
        ocf_log info "PostgreSQL start command sent."
    else
        ocf_log err "Can't start PostgreSQL."
        return $OCF_ERR_GENERIC
    fi

    while :
    do
        pgsql_real_monitor warn
        rc=$?
        if [ $rc -eq $OCF_SUCCESS -o $rc -eq $OCF_RUNNING_MASTER ]; then
            break;
        fi
        sleep 1
        ocf_log debug "PostgreSQL still hasn't started yet. Waiting..."
    done

    # delete replication slots on all nodes. On master node will be created during promotion.
    if use_replication_slot; then
        delete_replication_slots
        if [ $? -eq $OCF_ERR_GENERIC ]; then
            ocf_log err "PostgreSQL can't clean up replication_slot."
            return $OCF_ERR_GENERIC
        fi
    fi

    ocf_log info "PostgreSQL is started."
    return $rc
}

pgsql_replication_start() {
    local rc
    local synchronous_standby_names

    # initializing for replication
    change_pgsql_status "$NODENAME" "STOP"
    delete_master_baseline
    exec_with_retry 0 $CRM_MASTER -v $CAN_NOT_PROMOTE
    rm -f ${XLOG_NOTE_FILE}.* $REP_MODE_CONF $RECOVERY_CONF
    if ! make_recovery_conf || ! delete_xlog_location || ! set_async_mode_all; then
        return $OCF_ERR_GENERIC
    fi

    if [ -f $PGSQL_LOCK ]; then
        ocf_log err "My data may be inconsistent. You have to remove $PGSQL_LOCK file to force start."
        return $OCF_ERR_GENERIC
    fi

    # start
    pgsql_real_start
    if [ $? -ne $OCF_SUCCESS ]; then
        return $OCF_ERR_GENERIC
    fi

    synchronous_standby_names=$(exec_sql "${CHECK_SYNCHRONOUS_STANDBY_NAMES_SQL}")
    if [ -n "${synchronous_standby_names}" ]; then
        ocf_log err "Invalid synchronous_standby_names is set in postgresql.conf."
        return $OCF_ERR_CONFIGURED
    fi

    change_pgsql_status "$NODENAME" "HS:alone"
    return $OCF_SUCCESS
}

#pgsql_start: pgsql_real_start() wrapper for replication
pgsql_start() {
    if ! is_replication; then
        pgsql_real_start
        return $?
    else
        pgsql_replication_start
        return $?
    fi
}

#pgsql_promote: Promote PostgreSQL
pgsql_promote() {
    local target
    local rc

    if ! is_replication; then
        ocf_log err "Not in a replication mode."
        return $OCF_ERR_CONFIGURED
    fi
    rm -f ${XLOG_NOTE_FILE}.*

    for target in $NODE_LIST; do
        [ "$target" = "$NODENAME" ] && continue
        change_data_status "$target" "DISCONNECT"
        change_master_score "$target" "$CAN_NOT_PROMOTE"
    done

    ocf_log info "Creating $PGSQL_LOCK."
    touch $PGSQL_LOCK
    show_master_baseline

    # create replication slots on master before promotion
    if use_replication_slot; then
        create_replication_slots
        if [ $? -eq $OCF_ERR_GENERIC ]; then
            ocf_log err "PostgreSQL can't create replication_slot."
            return $OCF_ERR_GENERIC
        fi
    fi

    if ocf_is_true ${OCF_RESKEY_restart_on_promote}; then
        ocf_log info "Restarting PostgreSQL instead of promote."
        #stop : this function returns $OCF_SUCCESS only.
        pgsql_real_stop slave
        rm -f $RECOVERY_CONF
        pgsql_real_start
        rc=$?
        if [ $rc -ne $OCF_RUNNING_MASTER ]; then
            ocf_log err "Can't start PostgreSQL as primary on promote."
            if [ $rc -ne $OCF_SUCCESS ]; then
                change_pgsql_status "$NODENAME" "STOP"
            fi
            return $OCF_ERR_GENERIC
        fi
    else
        runasowner "$OCF_RESKEY_pgctl -D $OCF_RESKEY_pgdata -W promote"
        if [ $? -eq 0 ]; then
            ocf_log info "PostgreSQL promote command sent."
        else
            ocf_log err "Can't promote PostgreSQL."
            return $OCF_ERR_GENERIC
        fi

        while :
        do
            pgsql_real_monitor warn
            rc=$?
            if [ $rc -eq $OCF_RUNNING_MASTER ]; then
                break;
            elif [ $rc -eq $OCF_ERR_GENERIC ]; then
                ocf_log err "Can't promote PostgreSQL."
                return $rc
            fi
            sleep 1
            ocf_log debug "PostgreSQL still hasn't promoted yet. Waiting..."
        done
        ocf_log info "PostgreSQL is promoted."
    fi

    change_data_status "$NODENAME" "LATEST"
    exec_with_retry 0 $CRM_MASTER -v $PROMOTE_ME
    change_pgsql_status "$NODENAME" "PRI"
    return $OCF_SUCCESS
}

#pgsql_demote: Demote PostgreSQL
pgsql_demote() {
    local rc

    if ! is_replication; then
        ocf_log err "Not in a replication mode."
        return $OCF_ERR_CONFIGURED
    fi

    exec_with_retry 0 $CRM_MASTER -v $CAN_NOT_PROMOTE
    delete_master_baseline

    if ! pgsql_status; then
        ocf_log info "PostgreSQL is already stopped on demote."
    else
        ocf_log info "Stopping PostgreSQL on demote."
        pgsql_real_stop master
        rc=$?
        if [ "$rc" -ne "$OCF_SUCCESS" ]; then
            change_pgsql_status "$NODENAME" "UNKNOWN"
            return $rc
        fi
    fi
    change_pgsql_status "$NODENAME" "STOP"
    return $OCF_SUCCESS
}

#pgsql_real_stop: Stop PostgreSQL
pgsql_real_stop() {
    local rc
    local count
    local stop_escalate

    if ocf_is_true ${OCF_RESKEY_check_wal_receiver}; then
        attrd_updater -n "$PGSQL_WAL_RECEIVER_STATUS_ATTR" -D -q
    fi

    if ! pgsql_status
    then
        #Already stopped
        return $OCF_SUCCESS
    fi

    stop_escalate=$OCF_RESKEY_stop_escalate
    if [ "$1" = "slave" ]; then
        stop_escalate="$OCF_RESKEY_stop_escalate_in_slave"
    fi
    # adjust stop_escalate time when it is longer than the timeout
    if [ -n "$OCF_RESKEY_CRM_meta_timeout" ] && \
        [ "$stop_escalate" -ge $((OCF_RESKEY_CRM_meta_timeout/1000)) ]; then
        stop_escalate=$(((OCF_RESKEY_CRM_meta_timeout/1000) - 10))
        ocf_log info "stop_escalate(or stop_escalate_in_slave) time is adjusted to ${stop_escalate} based on the configured timeout."
    fi

    # Stop PostgreSQL, do not wait for clients to disconnect
    if [ $stop_escalate -gt 0 ]; then
            runasowner "$OCF_RESKEY_pgctl -W -D $OCF_RESKEY_pgdata stop -m fast"
    fi

    # stop waiting
    count=0
    while [ $count -lt $stop_escalate ]
    do
        if ! pgsql_status
        then
            #PostgreSQL stopped
            break;
        fi
        count=`expr $count + 1`
        sleep 1
    done

    if pgsql_status
    then
        #PostgreSQL is still up. Use another shutdown mode.
        ocf_log info "PostgreSQL failed to stop after ${stop_escalate}s using -m fast. Trying -m immediate..."
        runasowner "$OCF_RESKEY_pgctl -W -D $OCF_RESKEY_pgdata stop -m immediate"
    fi

    while :
    do
        pgsql_real_monitor
        rc=$?
        if [ $rc -eq $OCF_NOT_RUNNING ]; then
            # An unnecessary debug log is prevented.
            break;
        fi
        sleep 1
        ocf_log debug "PostgreSQL still hasn't stopped yet. Waiting..."
    done

    # Remove postmaster.pid if it exists
    rm -f $PIDFILE

    if  [ "$1" = "master" -a "$OCF_RESKEY_CRM_meta_notify_slave_uname" = " " ]; then
        ocf_log info "Removing $PGSQL_LOCK."
        rm -f $PGSQL_LOCK
    fi
    return $OCF_SUCCESS
}

pgsql_replication_stop() {
    local rc

    exec_with_retry 5 $CRM_MASTER -v $CAN_NOT_PROMOTE
    delete_xlog_location

    if ! pgsql_status
    then
        ocf_log info "PostgreSQL is already stopped."
        change_pgsql_status "$NODENAME" "STOP"
        return $OCF_SUCCESS
    fi

    pgsql_real_stop slave
    rc=$?
    if [ $rc -ne $OCF_SUCCESS ]; then
        change_pgsql_status "$NODENAME" "UNKNOWN"
        return $rc
    fi

    change_pgsql_status "$NODENAME" "STOP"
    set_async_mode_all
    delete_master_baseline
    return $OCF_SUCCESS
}

#pgsql_stop: pgsql_real_stop() wrapper for replication
pgsql_stop() {
    if ! is_replication; then
        pgsql_real_stop
        return $?
    else
        pgsql_replication_stop
        return $?
    fi
}

#
# pgsql_status: is PostgreSQL up?
#

pgsql_status() {
     if [ -f $PIDFILE ]
     then
         PID=`head -n 1 $PIDFILE`
         runasowner "kill -s 0 $PID >/dev/null 2>&1"
         return $?
     fi

     # No PID file
     false
}

pgsql_wal_receiver_status() {
    local PID
    local receiver_parent_pids
    local pgsql_real_monitor_status=$1

    PID=`head -n 1 $PIDFILE`
    receiver_parent_pids=`ps -ef | tr -s " " | grep "[w]al \?receiver" | cut -d " " -f 3`

    if echo "$receiver_parent_pids" | grep -q -w "$PID" ; then
        attrd_updater -n "$PGSQL_WAL_RECEIVER_STATUS_ATTR" -v "normal" -q
        return 0
    fi

    if [ $pgsql_real_monitor_status -eq "$OCF_RUNNING_MASTER" ]; then
        attrd_updater -n "$PGSQL_WAL_RECEIVER_STATUS_ATTR" -v "normal (master)" -q
        return 0
    fi

    attrd_updater -n "$PGSQL_WAL_RECEIVER_STATUS_ATTR" -v "ERROR" -q
    ocf_log warn "wal receiver process is not running"
    return 1
}

#
# pgsql_real_monitor
#

pgsql_real_monitor() {
    local loglevel
    local rc
    local output

    # Set the log level of the error message
    loglevel=${1:-err}

    if ! pgsql_status
    then
        ocf_log info "PostgreSQL is down"
        return $OCF_NOT_RUNNING
    fi

    if is_replication; then
        #Check replication state
        output=`exec_sql "${CHECK_MS_SQL}"`
        rc=$?

        if [ $rc -ne  0 ]; then
            report_psql_error $rc $loglevel "Can't get PostgreSQL recovery status."
            return $OCF_ERR_GENERIC
        fi

        case "$output" in
            f)  ocf_log debug "PostgreSQL is running as a primary."
                if [ "$OCF_RESKEY_monitor_sql" = "$OCF_RESKEY_monitor_sql_default" ]; then
                    return $OCF_RUNNING_MASTER
                fi
                ;;

            t)  ocf_log debug "PostgreSQL is running as a hot standby."
                return $OCF_SUCCESS;;

            *)  ocf_log err "$CHECK_MS_SQL output is $output"
                return $OCF_ERR_GENERIC;;
        esac
    fi

    OCF_RESKEY_monitor_sql=`escape_string "$OCF_RESKEY_monitor_sql"`
    runasowner -q $loglevel "$OCF_RESKEY_psql $psql_options \
                  -c '$OCF_RESKEY_monitor_sql'"
    rc=$?
    if [ $rc -ne  0 ]; then
        report_psql_error $rc $loglevel "PostgreSQL $OCF_RESKEY_pgdb isn't running."
        return $OCF_ERR_GENERIC
    fi

    if is_replication; then
        return $OCF_RUNNING_MASTER
    fi
    return $OCF_SUCCESS
}

pgsql_replication_monitor() {
    local rc

    rc=$1
    if [ $rc -ne $OCF_SUCCESS -a $rc -ne "$OCF_RUNNING_MASTER" ]; then
        return $rc
    fi
    # If I am Master
    if [ $rc -eq $OCF_RUNNING_MASTER ]; then
        change_data_status "$NODENAME" "LATEST"
        change_pgsql_status "$NODENAME" "PRI"
        control_slave_status || return $OCF_ERR_GENERIC
        if [ "$RE_CONTROL_SLAVE" = "true" ]; then
            sleep 2
            ocf_log info "re-controlling slave status."
            RE_CONTROL_SLAVE="none"
            control_slave_status || return $OCF_ERR_GENERIC
        fi
        return $rc
    fi

    # I can't get master node name from $OCF_RESKEY_CRM_meta_notify_master_uname on monitor,
    # so I will get master node name using crm_mon -n
    print_crm_mon | tr -d "\t" | tr -d " " | grep -q "^${RESOURCE_NAME}[(:].*[):].*Master"
    if [ $? -ne 0 ] ; then
        # If I am Slave and Master is not exist
        ocf_log info "Master does not exist."
        change_pgsql_status "$NODENAME" "HS:alone"
        have_master_right
        if [ $? -eq 0 ]; then
            rm -f ${XLOG_NOTE_FILE}.*
        fi
    else
        output=`exec_with_retry 0 $CRM_ATTR_FOREVER -N "$NODENAME" \
                -n "$PGSQL_DATA_STATUS_ATTR" -G -q`
        if [ "$output" = "DISCONNECT" ]; then
            change_pgsql_status "$NODENAME" "HS:alone"
        fi
    fi
    return $rc
}

#pgsql_monitor: pgsql_real_monitor() wrapper for replication
pgsql_monitor() {
    local rc

    pgsql_real_monitor
    rc=$?

    if ocf_is_true ${OCF_RESKEY_check_wal_receiver}; then
        pgsql_wal_receiver_status $rc
    fi

    if ! is_replication; then
        return $rc
    else
        pgsql_replication_monitor $rc
        return $?
    fi
}

# pgsql_post_demote
pgsql_post_demote() {
    DEMOTE_NODE=`echo $OCF_RESKEY_CRM_meta_notify_demote_uname | sed "s/ /\n/g" | head -1 | tr '[A-Z]' '[a-z]'`
    ocf_log debug "post-demote called. Demote uname is $DEMOTE_NODE"
    if [ "$DEMOTE_NODE" != "$NODENAME" ]; then
        if ! echo $OCF_RESKEY_CRM_meta_notify_master_uname | tr '[A-Z]' '[a-z]' | grep $NODENAME; then
            show_master_baseline
            change_pgsql_status "$NODENAME" "HS:alone"
        fi
    fi
    return $OCF_SUCCESS
}

pgsql_pre_promote() {
    local master_baseline
    local my_master_baseline
    local cmp_location
    local number_of_nodes

    # If my data is newer than new master's one, I fail my resource.
    PROMOTE_NODE=`echo $OCF_RESKEY_CRM_meta_notify_promote_uname | \
                  sed "s/ /\n/g" | head -1 | tr '[A-Z]' '[a-z]'`
    number_of_nodes=`echo $NODE_LIST | wc -w`
    if [ $number_of_nodes -ge 3 -a \
         "$OCF_RESKEY_rep_mode" = "sync" -a \
         "$PROMOTE_NODE" != "$NODENAME" ]; then
        master_baseline=`$CRM_ATTR_REBOOT -N "$PROMOTE_NODE" -n \
                         "$PGSQL_MASTER_BASELINE" -G -q 2>/dev/null`
        if [ $? -eq 0 ]; then
            my_master_baseline=`$CRM_ATTR_REBOOT -N "$NODENAME" -n \
                                "$PGSQL_MASTER_BASELINE" -G -q 2>/dev/null`
            # get older location
            cmp_location=`printf "$master_baseline\n$my_master_baseline\n" |\
                          sort | head -1`
            if [ "$cmp_location" != "$my_master_baseline" ]; then
                # We used to set the failcount to INF for the resource here in
                # order to move the master to the other node. However, setting
                # the failcount should be done only by the CRM and so this use
                # got deprecated in pacemaker version 1.1.17. Now we do the
                # "ban resource from the node".
                ocf_log err "My data is newer than new master's one. New master's location : $master_baseline"
                exec_with_retry 0 $CRM_RESOURCE -B -r $OCF_RESOURCE_INSTANCE -N $NODENAME -Q
                return $OCF_ERR_GENERIC
            fi
        fi
    fi
    return $OCF_SUCCESS
}

pgsql_notify() {
    local type="${OCF_RESKEY_CRM_meta_notify_type}"
    local op="${OCF_RESKEY_CRM_meta_notify_operation}"
    local rc

    if ! is_replication; then
        return $OCF_SUCCESS
    fi

    ocf_log debug "notify: ${type} for ${op}"
    case $type in
        pre)
            case $op in
                promote)
                    pgsql_pre_promote
                    return $?
                    ;;
            esac
            ;;
        post)
            case $op in
                promote)
                    delete_xlog_location
                    PROMOTE_NODE=`echo $OCF_RESKEY_CRM_meta_notify_promote_uname | \
                                  sed "s/ /\n/g" | head -1 | tr '[A-Z]' '[a-z]'`
                    if [ "$PROMOTE_NODE" != "$NODENAME" ]; then
                        delete_master_baseline
                    fi
                    return $OCF_SUCCESS
                    ;;
                demote)
                    pgsql_post_demote
                    return $?
                    ;;
                start|stop)
                    MASTER_NODE=`echo $OCF_RESKEY_CRM_meta_notify_master_uname | \
                                  sed "s/ /\n/g" | head -1 | tr '[A-Z]' '[a-z]'`
                    if [ "$NODENAME" = "$MASTER_NODE" ]; then
                        control_slave_status
                    fi
                    return $OCF_SUCCESS
                    ;;
            esac
            ;;
    esac
    return $OCF_SUCCESS
}

control_slave_status() {
    local rc
    local data_status
    local target
    local all_data_status
    local tmp_data_status
    local number_of_nodes

    all_data_status=`exec_sql "${CHECK_REPLICATION_STATE_SQL}"`
    rc=$?

    if [ $rc -eq 0 ]; then
        if [ -n "$all_data_status" ]; then
            all_data_status=`echo $all_data_status | sed "s/\n/ /g"`
        fi
    else
        report_psql_error $rc err "Can't get PostgreSQL replication status."
        return 1
    fi

    number_of_nodes=`echo $NODE_LIST | wc -w`
    for target in $NODE_LIST; do
        if [ "$target" = "$NODENAME" ]; then
            continue
        fi

        data_status="DISCONNECT"
        if [ -n "$all_data_status" ]; then
            for tmp_data_status in $all_data_status; do
                if ! echo $tmp_data_status | grep -q "^${target}|"; then
                    continue
                fi
                data_status=`echo $tmp_data_status | cut -d "|" -f 2,3`
                ocf_log debug "node_name and data_status is $tmp_data_status"
                break
            done
        fi

        case "$data_status" in
            "STREAMING|SYNC")
                change_data_status "$target" "$data_status"
                change_master_score "$target" "$CAN_PROMOTE"
                change_pgsql_status "$target" "HS:sync"
                ;;
            "STREAMING|ASYNC")
                change_data_status "$target" "$data_status"
                if [ "$OCF_RESKEY_rep_mode" = "sync" ]; then
                    change_master_score "$target" "$CAN_NOT_PROMOTE"
                    set_sync_mode "$target"
                else
                    if [ $number_of_nodes -le 2 ]; then
                        change_master_score "$target" "$CAN_PROMOTE"
                    else
                        # I can't determine which slave's data is newest in async mode.
                        change_master_score "$target" "$CAN_NOT_PROMOTE"
                    fi
                fi
                change_pgsql_status "$target" "HS:async"
                ;;
            "STREAMING|POTENTIAL")
                change_data_status "$target" "$data_status"
                change_master_score "$target" "$CAN_NOT_PROMOTE"
                change_pgsql_status "$target" "HS:potential"
                ;;
            "DISCONNECT")
                change_data_status "$target" "$data_status"
                change_master_score "$target" "$CAN_NOT_PROMOTE"
                if [ "$OCF_RESKEY_rep_mode" = "sync" ]; then
                    set_async_mode "$target"
                fi
                ;;
            *)
                change_data_status "$target" "$data_status"
                change_master_score "$target" "$CAN_NOT_PROMOTE"
                if [ "$OCF_RESKEY_rep_mode" = "sync" ]; then
                    set_async_mode "$target"
                fi
                change_pgsql_status "$target" "HS:connected"
                ;;
        esac
    done
    return 0
}

have_master_right() {
    local old
    local new
    local output
    local data_status
    local node
    local mylocation
    local count
    local newestXlog
    local oldfile
    local newfile

    ocf_log debug "Checking if I have a master right."

    data_status=`$CRM_ATTR_FOREVER -N "$NODENAME" -n \
                 "$PGSQL_DATA_STATUS_ATTR" -G -q 2>/dev/null`
    if [ "$OCF_RESKEY_rep_mode" = "sync" ]; then
        if [ -n "$data_status" -a "$data_status" != "STREAMING|SYNC" -a \
             "$data_status" != "LATEST" ]; then
            ocf_log warn "My data is out-of-date. status=$data_status"
            return 1
        fi
    else
        if [ -n "$data_status" -a "$data_status" != "STREAMING|SYNC" -a \
             "$data_status" != "STREAMING|ASYNC" -a \
             "$data_status" != "LATEST" ]; then
            ocf_log warn "My data is out-of-date. status=$data_status"
            return 1
        fi
    fi
    ocf_log info "My data status=$data_status."

    show_xlog_location
    if [ $? -ne 0 ]; then
        ocf_log err "Failed to show my xlog location."
        exit $OCF_ERR_GENERIC
    fi

    old=0
    for count in `seq $OCF_RESKEY_xlog_check_count`; do
       if [ -f ${XLOG_NOTE_FILE}.$count ]; then
           old=$count
           continue
       fi
       break
    done
    new=`expr $old + 1`

    # get xlog locations of all nodes
    for node in ${NODE_LIST}; do
        output=`$CRM_ATTR_REBOOT -N "$node" -n \
                "$PGSQL_XLOG_LOC_NAME" -G -q 2>/dev/null`
        if [ $? -ne 0 ]; then
            ocf_log warn "Can't get $node xlog location."
            continue
        else
            ocf_log info "$node xlog location : $output"
            echo "$node $output" >> ${XLOG_NOTE_FILE}.${new}
            if [ "$node" = "$NODENAME" ]; then
                mylocation=$output
            fi
        fi
    done

    oldfile=`cat ${XLOG_NOTE_FILE}.${old} 2>/dev/null`
    newfile=`cat ${XLOG_NOTE_FILE}.${new} 2>/dev/null`
    if [ "$oldfile" != "$newfile" ]; then
        # reset counter
        rm -f ${XLOG_NOTE_FILE}.*
        printf "$newfile\n" > ${XLOG_NOTE_FILE}.0
        return 1
    fi

    if [ "$new" -ge "$OCF_RESKEY_xlog_check_count" ]; then
        newestXlog=`printf "$newfile\n" | sort -t " " -k 2,3 -r | \
                    head -1 | cut -d " " -f 2`
        if [ "$newestXlog" = "$mylocation" ]; then
            ocf_log info "I have a master right."
            exec_with_retry 5 $CRM_MASTER -v $PROMOTE_ME
            return 0
        fi
        change_data_status "$NODENAME" "DISCONNECT"
        ocf_log info "I don't have correct master data."
        # reset counter
        rm -f ${XLOG_NOTE_FILE}.*
        printf "$newfile\n" > ${XLOG_NOTE_FILE}.0
    fi

    return 1
}

is_replication() {
    if [ "$OCF_RESKEY_rep_mode" != "none" -a "$OCF_RESKEY_rep_mode" != "slave" ]; then
        return 0
    fi
    return 1
}

use_replication_slot() {
    if [ -n "$OCF_RESKEY_replication_slot_name" ]; then
        return 0
    fi

    return 1
}

create_replication_slot_name() {
    local number_of_nodes=0
    local target
    local replication_slot_name
    local replication_slot_name_list_tmp
    local replication_slot_name_list

    if [ -n "$NODE_LIST" ]; then
        number_of_nodes=`echo $NODE_LIST | wc -w`
    fi

    if [ $number_of_nodes -le 0 ]; then
        replication_slot_name_list=""

    # The Master node should have some slots equal to the number of Slaves, and
    # the Slave nodes connect to their dedicated slot on the Master.
    # To ensuring that the slots name are each unique, add postfix to $OCF_RESKEY_replication_slot.
    # The postfix is "_$target".
    else
        for target in $NODE_LIST
        do
            if [ "$target" != "$NODENAME" ]; then
                # The Uppercase, "-" and "." don't allow to use in slot_name.
                # If the NODENAME contains them, convert upper case to lower case and "_" and "." to "_".
                target=`echo "$target" | tr 'A-Z.-' 'a-z__'`
                replication_slot_name="$OCF_RESKEY_replication_slot_name"_"$target"
                replication_slot_name_list_tmp="$replication_slot_name_list"
                replication_slot_name_list="$replication_slot_name_list_tmp $replication_slot_name"
            fi
        done
    fi

    echo $replication_slot_name_list
}

delete_replication_slot(){
    DELETE_REPLICATION_SLOT_sql="SELECT pg_drop_replication_slot('$1');"
    output=`exec_sql "$DELETE_REPLICATION_SLOT_sql"`
    return $?
}

delete_replication_slots() {
    local replication_slot_name_list
    local replication_slot_name

    replication_slot_name_list=`create_replication_slot_name`
    ocf_log debug "replication slot names are $replication_slot_name_list."

    for replication_slot_name in $replication_slot_name_list
    do
        if [ `check_replication_slot $replication_slot_name` = "1" ]; then
            delete_replication_slot $replication_slot_name
            if [ $? -eq 0 ]; then
                ocf_log info "PostgreSQL delete the replication slot($replication_slot_name)."
            else
                ocf_log err "$output"
                return $OCF_ERR_GENERIC
            fi
        fi
    done
}

create_replication_slots() {
    local replication_slot_name
    local replication_slot_name_list
    local output
    local rc
    local CREATE_REPLICATION_SLOT_sql
    local DELETE_REPLICATION_SLOT_sql

    replication_slot_name_list=`create_replication_slot_name`
    ocf_log debug "replication slot names are $replication_slot_name_list."

    for replication_slot_name in $replication_slot_name_list
    do
        # If the same name slot is already exists, initialize(delete and create) the slot.
        if [ `check_replication_slot $replication_slot_name` = "1" ]; then
            delete_replication_slot $replication_slot_name
            if [ $? -eq 0 ]; then
                ocf_log info "PostgreSQL delete the replication slot($replication_slot_name)."
            else
                ocf_log err "$output"
                return $OCF_ERR_GENERIC
            fi
        fi

        CREATE_REPLICATION_SLOT_sql="SELECT pg_create_physical_replication_slot('$replication_slot_name');"
        output=`exec_sql "$CREATE_REPLICATION_SLOT_sql"`
        rc=$?

        if [ $rc -eq 0 ]; then
            ocf_log info "PostgreSQL creates the replication slot($replication_slot_name)."
        else
            ocf_log err "$output"
            return $OCF_ERR_GENERIC
        fi
    done

    return 0
}

# This function check the replication slot does exists.
check_replication_slot(){
    local replication_slot_name=$1
    local output
    local CHECK_REPLICATION_SLOT_sql="SELECT count(*) FROM pg_replication_slots WHERE slot_name = '$replication_slot_name'"

    output=`exec_sql "$CHECK_REPLICATION_SLOT_sql"`
    echo "$output"
}

# On postgreSQL 10 or later, "location" means "lsn".
get_my_location() {
    local rc
    local output
    local replay_loc
    local receive_loc
    local output1
    local output2
    local log1
    local log2
    local newer_location

    output=`exec_sql "$CHECK_XLOG_LOC_SQL"`
    rc=$?

    if [ $rc -ne 0 ]; then
        report_psql_error $rc err "Can't get my xlog location."
        return 1
    fi
    replay_loc=`echo $output | cut -d "|" -f 1`
    receive_loc=`echo $output | cut -d "|" -f 2`

    output1=`echo "$replay_loc" | cut -d "/" -f 1`
    output2=`echo "$replay_loc" | cut -d "/" -f 2`
    log1=`printf "%08s\n" $output1 | sed "s/ /0/g"`
    log2=`printf "%08s\n" $output2 | sed "s/ /0/g"`
    replay_loc="${log1}${log2}"

    output1=`echo "$receive_loc" | cut -d "/" -f 1`
    output2=`echo "$receive_loc" | cut -d "/" -f 2`
    log1=`printf "%08s\n" $output1 | sed "s/ /0/g"`
    log2=`printf "%08s\n" $output2 | sed "s/ /0/g"`
    receive_loc="${log1}${log2}"

    newer_location=`printf "$replay_loc\n$receive_loc" | sort -r | head -1`
    echo "$newer_location"
    return 0
}

# On postgreSQL 10 or later, "xlog_location" means "wal_lsn".
show_xlog_location() {
    local location

    location=`get_my_location` || return 1
    exec_with_retry 0 $CRM_ATTR_REBOOT -N "$NODENAME" -n "$PGSQL_XLOG_LOC_NAME" -v "$location"
}

# On postgreSQL 10 or later, "xlog_location" means "wal_lsn".
delete_xlog_location() {
    exec_with_retry 5 $CRM_ATTR_REBOOT -N "$NODENAME" -n "$PGSQL_XLOG_LOC_NAME" -D
}

show_master_baseline() {
    local rc
    local location

    location=`get_my_location`
    ocf_log info "My master baseline : $location."
    exec_with_retry 0 $CRM_ATTR_REBOOT -N "$NODENAME" -n "$PGSQL_MASTER_BASELINE" -v "$location"
}

delete_master_baseline() {
    exec_with_retry 5 $CRM_ATTR_REBOOT -N "$NODENAME" -n "$PGSQL_MASTER_BASELINE" -D
}

set_async_mode_all() {
    [ "$OCF_RESKEY_rep_mode" = "sync" ] || return 0
    ocf_log info "Set all nodes into async mode."
    runasowner -q err "echo \"synchronous_standby_names = ''\" > \"$REP_MODE_CONF\""
    if [ $? -ne 0 ]; then
        ocf_log err "Can't set all nodes into async mode."
        return 1
    fi
    return 0
}

set_async_mode() {
    cat $REP_MODE_CONF |  grep -q -E "(\"$1\")|([,' ]$1[,' ])"
    if [ $? -eq 0 ]; then
        ocf_log info "Setup $1 into async mode."
        runasowner -q err "echo \"synchronous_standby_names = ''\" > \"$REP_MODE_CONF\""
    else
        ocf_log debug "$1 is already in async mode."
        return 0
    fi
    exec_with_retry 0 reload_conf
}

set_sync_mode() {
    local sync_node_in_conf

    sync_node_in_conf=`cat $REP_MODE_CONF | cut -d "'" -f 2`
    if [ -n "$sync_node_in_conf" ]; then
        ocf_log debug "$sync_node_in_conf is already sync mode."
    else
        ocf_log info "Setup $1 into sync mode."
        runasowner -q err "echo \"synchronous_standby_names = '\\\"$1\\\"'\" > \"$REP_MODE_CONF\""
        [ "$RE_CONTROL_SLAVE" = "false" ] && RE_CONTROL_SLAVE="true"
        exec_with_retry 0 reload_conf
    fi
}

reload_conf() {
    # Invoke pg_ctl
    runasowner "$OCF_RESKEY_pgctl -D $OCF_RESKEY_pgdata reload"
    if [ $? -eq 0 ]; then
        ocf_log info "Reload configuration file."
    else
        ocf_log err "Can't reload configuration file."
        return 1
    fi

    return 0
}

user_recovery_conf() {
    local nodename_tmp

    # put archive_cleanup_command and recovery_end_command only when defined by user
    if [ -n "$OCF_RESKEY_archive_cleanup_command" ]; then
        echo "archive_cleanup_command = '${OCF_RESKEY_archive_cleanup_command}'"
    fi
    if [ -n "$OCF_RESKEY_recovery_end_command" ]; then
        echo "recovery_end_command = '${OCF_RESKEY_recovery_end_command}'"
    fi

    if use_replication_slot; then
        nodename_tmp=`echo "$NODENAME" | tr 'A-Z.-' 'a-z__'`
        echo "primary_slot_name = '${OCF_RESKEY_replication_slot_name}_$nodename_tmp'"
    fi
}

make_recovery_conf() {
    runasowner "touch $RECOVERY_CONF"
    if [ $? -ne 0 ]; then
        ocf_log err "Can't create recovery.conf."
        return 1
    fi

cat > $RECOVERY_CONF <<END
standby_mode = 'on'
primary_conninfo = 'host=${OCF_RESKEY_master_ip} port=${OCF_RESKEY_pgport} user=${OCF_RESKEY_repuser} application_name=${NODENAME} ${OCF_RESKEY_primary_conninfo_opt}'
restore_command = '${OCF_RESKEY_restore_command}'
recovery_target_timeline = 'latest'
END

    user_recovery_conf >> $RECOVERY_CONF
    ocf_log debug "Created recovery.conf. host=${OCF_RESKEY_master_ip}, user=${OCF_RESKEY_repuser}"
    return 0
}

# change pgsql-status.
# arg1:node, arg2: value
change_pgsql_status() {
    local output

    if ! is_node_online $1; then
        return 0
    fi

    output=`$CRM_ATTR_REBOOT -N "$1" -n "$PGSQL_STATUS_ATTR" -G -q 2>/dev/null`
    if [ "$output" != "$2" ]; then
        # If slave's disk is broken, RA cannot read PID file
        # and misjudges the PostgreSQL as down while it is running.
        # It causes overwriting of pgsql-status by Master because replication is still connected.
        if [ "$output" = "STOP" -o "$output" = "UNKNOWN" ]; then
            if [ "$1" != "$NODENAME" ]; then
                ocf_log warn "Changing $PGSQL_STATUS_ATTR on $1 : $output->$2 by $NODENAME is prohibited."
                return 0
            fi
        fi
        ocf_log info "Changing $PGSQL_STATUS_ATTR on $1 : $output->$2."
        exec_with_retry 0 $CRM_ATTR_REBOOT -N "$1" -n "$PGSQL_STATUS_ATTR" -v "$2"
    fi
    return 0
}

# change pgsql-data-status.
# arg1:node, arg2: value
change_data_status() {
    local output

    if ! node_exist $1; then
        return 0
    fi

    while :
    do
        output=`$CRM_ATTR_FOREVER -N "$1" -n "$PGSQL_DATA_STATUS_ATTR" -G -q 2>/dev/null`
        if [ "$output" != "$2" ]; then
            ocf_log info "Changing $PGSQL_DATA_STATUS_ATTR on $1 : $output->$2."
            exec_with_retry 0 exec_with_timeout 0 "$CRM_ATTR_FOREVER" -N $1 -n $PGSQL_DATA_STATUS_ATTR -v "$2"
        else
            break
        fi
    done
    return 0
}

# set master-score
# arg1:node, arg2: score, arg3: resoure
set_master_score() {
    local current_score

    current_score=`$CRM_ATTR_REBOOT -N "$1" -n "master-$3" -G -q 2>/dev/null`
    if [ -n "$current_score" -a "$current_score" != "$2" ]; then
        ocf_log info "Changing $3 master score on $1 : $current_score->$2."
        exec_with_retry 0 $CRM_ATTR_REBOOT -N "$1" -n "master-$3" -v "$2"
    fi
    return 0
}

# change master-score
# arg1:node, arg2: score
change_master_score() {
    local instance

    if ! is_node_online $1; then
        return 0
    fi

    if echo $OCF_RESOURCE_INSTANCE | grep -q ":"; then
        # If Pacemaker version is 1.0.x
        instance=0
        while :
        do
            if [ "$instance" -ge "$OCF_RESKEY_CRM_meta_clone_max" ]; then
                break
            fi
            if [ "${RESOURCE_NAME}:${instance}" = "$OCF_RESOURCE_INSTANCE" ]; then
                instance=`expr $instance + 1`
                continue
            fi
            set_master_score $1 $2 "${RESOURCE_NAME}:${instance}" || return 1
            instance=`expr $instance + 1`
        done
    else
        # If globally-unique=false and Pacemaker version is 1.1.8 or higher
        # Master/Slave resource has no instance number
        set_master_score $1 $2 ${RESOURCE_NAME} || return 1
    fi
    return 0
}

report_psql_error()
{
    local rc
    local loglevel
    local message

    rc=$1
    loglevel=${2:-err}
    message="$3"

    ocf_log $loglevel "$message rc=$rc"
    if [ $rc -eq 1 ]; then
        ocf_log err "Fatal error (out of memory, file not found, etc.) occurred while executing the psql command."
    elif [ $rc -eq 2 ]; then
        ocf_log $loglevel "Connection error (connection to the server went bad and the session was not interactive) occurred while executing the psql command."
    elif [ $rc -eq 3 ]; then
        ocf_log err "Script error (the variable ON_ERROR_STOP was set) occurred while executing the psql command."
    fi
}

#
# timeout management function
# arg1   timeout >= 0 (if arg1 is 0, OCF_RESKEY_crm_attr_timeout is used.)
# arg2 : command
# arg3 : command's args
exec_with_timeout() {
    local func_pid
    local count=$OCF_RESKEY_crm_attr_timeout
    local rc

    if [ "$1" -ne 0 ]; then
        count=$1
    fi
    shift

    $* &
    func_pid=$!
    sleep .1

    while kill -s 0 $func_pid >/dev/null 2>&1; do
        sleep 1
        count=`expr $count - 1`
        if [ $count -le 0 ]; then
            ocf_log err "\"$*\" (pid=$func_pid) timed out."
            kill -s 9 $func_pid >/dev/null 2>&1
            return 1
        fi
        ocf_log info "Waiting($count). \"$*\" (pid=$func_pid)."
    done
    wait $func_pid
}

# retry command when command doesn't return 0
# arg1       : count >= 0 (if arg1 is 0, it retries command in infinitum(1day))
# arg2..argN : command and args
exec_with_retry() {
    local count="86400"
    local output
    local rc

    if [ "$1" -ne 0 ]; then
        count=$1
    fi
    shift

    while [ $count -gt 0 ]; do
        output=`$*`
        rc=$?
        if [ $rc -ne 0 ]; then
            ocf_log warn "Retrying(remain $count). \"$*\" failed. rc=$rc. stdout=\"$output\"."
            count=`expr $count - 1`
            sleep 1
        else
            printf "${output}"
            return 0
        fi
    done

    ocf_log err "giving up executing \"$*\""
    return $rc
}

is_node_online() {
    print_crm_mon | tr '[A-Z]' '[a-z]' | grep -e "^node $1 " -e "^node $1:" | grep -q -v "offline"
}

node_exist() {
    print_crm_mon | tr '[A-Z]' '[a-z]' | grep -q "^node $1"
}

check_binary2() {
    if ! have_binary "$1"; then
        ocf_log err "Setup problem: couldn't find command: $1"
        return 1
    fi
    return 0
}

check_config() {
    local rc=0

    if [ ! -f "$1" ]; then
        if ocf_is_probe; then
           ocf_log info "Configuration file is $1 not readable during probe."
           rc=1
        else
           ocf_log err "Configuration file $1 doesn't exist"
           rc=2
        fi
    fi

    return $rc
}

# Validate most critical parameters
pgsql_validate_all() {
    local version
    local check_config_rc
    local rep_mode_string
    local socket_directories
    local rc

    version=`cat $OCF_RESKEY_pgdata/PG_VERSION`

    if ! check_binary2 "$OCF_RESKEY_pgctl" ||
       ! check_binary2 "$OCF_RESKEY_psql"; then
        return $OCF_ERR_INSTALLED
    fi

    check_config "$OCF_RESKEY_config"
    check_config_rc=$?
    [ $check_config_rc -eq 2 ] && return $OCF_ERR_INSTALLED
    if [ $check_config_rc -eq 0 ]; then
        ocf_version_cmp "$version" "9.3"
        if [ $? -eq 0 ]; then
            : ${OCF_RESKEY_socketdir=`get_pgsql_param unix_socket_directory`}
        else
            # unix_socket_directories is used by PostgreSQL 9.3 or higher.
            socket_directories=`get_pgsql_param unix_socket_directories`
            if [ -n "$socket_directories" ]; then
                # unix_socket_directories may have multiple socket directories and the pgsql RA can not know which directory is used for psql command.
                # Therefore, the user must set OCF_RESKEY_socketdir explicitly.
                if [ -z "$OCF_RESKEY_socketdir" ]; then
                    ocf_log err "In PostgreSQL 9.3 or higher, socketdir can't be empty if you define unix_socket_directories in the postgresql.conf."
                    return $OCF_ERR_CONFIGURED
                fi
            fi
        fi
    fi

    getent passwd $OCF_RESKEY_pgdba >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
        ocf_log err "User $OCF_RESKEY_pgdba doesn't exist";
        return $OCF_ERR_INSTALLED;
    fi

    if ocf_is_probe; then
        ocf_log info "Don't check $OCF_RESKEY_pgdata during probe"
    else
        if ! runasowner "test -w $OCF_RESKEY_pgdata"; then
            ocf_log err "Directory $OCF_RESKEY_pgdata is not writable by $OCF_RESKEY_pgdba"
            return $OCF_ERR_PERM;
        fi
    fi

    if [ -n "$OCF_RESKEY_monitor_user" -a ! -n "$OCF_RESKEY_monitor_password" ]
    then
        ocf_log err "monitor password can't be empty"
        return $OCF_ERR_CONFIGURED
    fi

    if [ ! -n "$OCF_RESKEY_monitor_user" -a -n "$OCF_RESKEY_monitor_password" ]
    then
        ocf_log err "monitor_user has to be set if monitor_password is set"
        return $OCF_ERR_CONFIGURED
    fi

    if is_replication || [ "$OCF_RESKEY_rep_mode" = "slave" ]; then
        if [ `printf "$version\n9.1" | sort -n | head -1` != "9.1" ]; then
            ocf_log err "Replication mode needs PostgreSQL 9.1 or higher."
            return $OCF_ERR_INSTALLED
        fi
        if [ ! -n "$OCF_RESKEY_master_ip" ]; then
            ocf_log err "master_ip can't be empty."
            return $OCF_ERR_CONFIGURED
        fi
    fi

    if is_replication; then
        REP_MODE_CONF=${OCF_RESKEY_tmpdir}/rep_mode.conf
        PGSQL_LOCK=${OCF_RESKEY_tmpdir}/PGSQL.lock
        XLOG_NOTE_FILE=${OCF_RESKEY_tmpdir}/xlog_note

        CRM_MASTER="${HA_SBIN_DIR}/crm_master -l reboot"
        CRM_ATTR_REBOOT="${HA_SBIN_DIR}/crm_attribute -l reboot"
        CRM_ATTR_FOREVER="${HA_SBIN_DIR}/crm_attribute -l forever"
        CRM_RESOURCE="${HA_SBIN_DIR}/crm_resource"

        CAN_NOT_PROMOTE="-INFINITY"
        CAN_PROMOTE="100"
        PROMOTE_ME="1000"

        CHECK_MS_SQL="select pg_is_in_recovery()"
        CHECK_SYNCHRONOUS_STANDBY_NAMES_SQL="show synchronous_standby_names"
        ocf_version_cmp "$version" "10"
        rc=$?
        if [ $rc -eq 1 ]||[ $rc -eq 2 ]; then
            CHECK_XLOG_LOC_SQL="select pg_last_wal_replay_lsn(),pg_last_wal_receive_lsn()"
        else
            CHECK_XLOG_LOC_SQL="select pg_last_xlog_replay_location(),pg_last_xlog_receive_location()"
        fi
        CHECK_REPLICATION_STATE_SQL="select application_name,upper(state),upper(sync_state) from pg_stat_replication"

        PGSQL_STATUS_ATTR="${RESOURCE_NAME}-status"
        PGSQL_DATA_STATUS_ATTR="${RESOURCE_NAME}-data-status"
        PGSQL_XLOG_LOC_NAME="${RESOURCE_NAME}-xlog-loc"
        PGSQL_MASTER_BASELINE="${RESOURCE_NAME}-master-baseline"

        NODE_LIST=`echo $OCF_RESKEY_node_list | tr '[A-Z]' '[a-z]'`
        RE_CONTROL_SLAVE="false"

        if ! ocf_is_ms; then
            ocf_log err "Replication(rep_mode=async or sync) requires Master/Slave configuration."
            return $OCF_ERR_CONFIGURED
        fi
        if [ ! "$OCF_RESKEY_rep_mode" = "sync" -a ! "$OCF_RESKEY_rep_mode" = "async" ]; then
            ocf_log err "Invalid rep_mode : $OCF_RESKEY_rep_mode"
            return $OCF_ERR_CONFIGURED
        fi
        if [ ! -n "$NODE_LIST" ]; then
            ocf_log err "node_list can't be empty."
            return $OCF_ERR_CONFIGURED
        fi
        if [ $check_config_rc -eq 0 ]; then
            rep_mode_string="include '$REP_MODE_CONF' # added by pgsql RA"
            if [ "$OCF_RESKEY_rep_mode" = "sync" ]; then
                if ! grep -q "^[[:space:]]*$rep_mode_string" $OCF_RESKEY_config; then
                    ocf_log info "adding include directive into $OCF_RESKEY_config"
                    echo "$rep_mode_string" >> $OCF_RESKEY_config
                fi
            else
                if grep -q "$rep_mode_string" $OCF_RESKEY_config; then
                    ocf_log info "deleting include directive from $OCF_RESKEY_config"
                    rep_mode_string=`echo $rep_mode_string | sed -e 's|/|\\\\/|g'`
                    sed -i "/$rep_mode_string/d" $OCF_RESKEY_config
                fi
            fi
        fi
        if ! mkdir -p $OCF_RESKEY_tmpdir || ! chown $OCF_RESKEY_pgdba $OCF_RESKEY_tmpdir || ! chmod 700 $OCF_RESKEY_tmpdir; then
            ocf_log err "Can't create directory $OCF_RESKEY_tmpdir or it is not readable by $OCF_RESKEY_pgdba"
            return $OCF_ERR_PERM
        fi
    fi

    if [ "$OCF_RESKEY_rep_mode" = "slave" ]; then
        if ocf_is_ms; then
            ocf_log err "Replication(rep_mode=slave) does not support Master/Slave configuration."
            return $OCF_ERR_CONFIGURED
        fi
    fi

    if use_replication_slot; then
        ocf_version_cmp "$version" "9.4"
        rc=$?
        if [ $rc -eq 0 ]||[ $rc -eq 3 ]; then
            ocf_log err "Replication slot needs PostgreSQL 9.4 or higher."
            return $OCF_ERR_CONFIGURED
        fi

        echo "$OCF_RESKEY_replication_slot_name" | grep -q -e '[^a-z0-9_]'
        if [ $? -eq 0 ]; then
            ocf_log err "Invalid replication_slot_name($OCF_RESKEY_replication_slot_name). only use lower case letters, numbers, and the underscore character."
            return $OCF_ERR_CONFIGURED
        fi
    fi

    return $OCF_SUCCESS
}


#
# Check if we need to create a log file
#

check_log_file() {
    if [ ! -e "$1" ]
    then
        touch $1 > /dev/null 2>&1
        chown $OCF_RESKEY_pgdba:`getent passwd $OCF_RESKEY_pgdba | cut -d ":" -f 4` $1
    fi

    #Check if $OCF_RESKEY_pgdba can write to the log file
    if ! runasowner "test -w $1"
    then
        return 1
    fi

    return 0
}

#
# Check if we need to create stats temp directory in tmpfs
#

check_stat_temp_directory() {
    local stats_temp

    stats_temp=`get_pgsql_param stats_temp_directory`

    if [ -z "$stats_temp" ]; then
        return
    fi

    if [ "${stats_temp#/}" = "$stats_temp" ]; then
        stats_temp="$OCF_RESKEY_pgdata/$stats_temp"
    fi

    if [ -d "$stats_temp" ]; then
        return
    fi

    if ! mkdir -p "$stats_temp"; then
        ocf_log err "Can't create directory $stats_temp"
        exit $OCF_ERR_PERM
    fi

    if ! chown $OCF_RESKEY_pgdba: "$stats_temp"; then
        ocf_log err "Can't change ownership for $stats_temp"
        exit $OCF_ERR_PERM
    fi

    if ! chmod 700 "$stats_temp"; then
        ocf_log err "Can't change permissions for $stats_temp"
        exit $OCF_ERR_PERM
    fi
}

#
# Check socket directory
#
check_socket_dir() {
    if [ ! -d "$OCF_RESKEY_socketdir" ]; then
        if ! mkdir "$OCF_RESKEY_socketdir"; then
            ocf_log err "Can't create directory $OCF_RESKEY_socketdir"
            exit $OCF_ERR_PERM
        fi

        if ! chown $OCF_RESKEY_pgdba:`getent passwd \
             $OCF_RESKEY_pgdba | cut -d ":" -f 4` "$OCF_RESKEY_socketdir"
        then
            ocf_log err "Can't change ownership for $OCF_RESKEY_socketdir"
            exit $OCF_ERR_PERM
        fi

        if ! chmod 2775 "$OCF_RESKEY_socketdir"; then
            ocf_log err "Can't change permissions for $OCF_RESKEY_socketdir"
            exit $OCF_ERR_PERM
        fi
    else
        if ! runasowner "touch $OCF_RESKEY_socketdir/test.$$"; then
            ocf_log err "$OCF_RESKEY_pgdba can't create files in $OCF_RESKEY_socketdir"
            exit $OCF_ERR_PERM
        fi
        rm $OCF_RESKEY_socketdir/test.$$
    fi
}

print_crm_mon() {
    if [ -z "$CRM_MON_OUTPUT" ]; then
        CRM_MON_OUTPUT=`exec_with_retry 0 crm_mon -n1`
    fi
    printf "${CRM_MON_OUTPUT}\n"
}

#
#   'main' starts here...
#


if [ $# -ne 1 ]
then
    usage
    exit $OCF_ERR_GENERIC
fi

PIDFILE=${OCF_RESKEY_pgdata}/postmaster.pid
BACKUPLABEL=${OCF_RESKEY_pgdata}/backup_label
RESOURCE_NAME=`echo $OCF_RESOURCE_INSTANCE | cut -d ":" -f 1`
PGSQL_WAL_RECEIVER_STATUS_ATTR="${RESOURCE_NAME}-receiver-status"
RECOVERY_CONF=${OCF_RESKEY_pgdata}/recovery.conf
NODENAME=$(ocf_local_nodename | tr '[A-Z]' '[a-z]')

case "$1" in
    methods)    pgsql_methods
                exit $?;;

    meta-data)  meta_data
                exit $OCF_SUCCESS;;
esac

pgsql_validate_all
rc=$?

[ "$1" = "validate-all" ] && exit $rc

if [ $rc -ne 0 ]
then
    case "$1" in
        stop)    if is_replication; then
                    change_pgsql_status "$NODENAME" "UNKNOWN"
                 fi
                 exit $OCF_SUCCESS;;
        monitor) exit $OCF_NOT_RUNNING;;
        status)  exit $OCF_NOT_RUNNING;;
        *)       exit $rc;;
    esac
fi

US=`id -u -n`

if [ $US != root -a $US != $OCF_RESKEY_pgdba ]
then
    ocf_log err "$0 must be run as root or $OCF_RESKEY_pgdba"
    exit $OCF_ERR_GENERIC
fi

# make psql command options
if [ -n "$OCF_RESKEY_monitor_user" ]; then
    PGUSER=$OCF_RESKEY_monitor_user; export PGUSER
    PGPASSWORD=$OCF_RESKEY_monitor_password; export PGPASSWORD
    psql_options="-p $OCF_RESKEY_pgport $OCF_RESKEY_pgdb"
else
    psql_options="-p $OCF_RESKEY_pgport -U $OCF_RESKEY_pgdba $OCF_RESKEY_pgdb"
fi

if [ -n "$OCF_RESKEY_pghost" ]; then
    psql_options="$psql_options -h $OCF_RESKEY_pghost"
else
    if [ -n "$OCF_RESKEY_socketdir" ]; then
        psql_options="$psql_options -h $OCF_RESKEY_socketdir"
    fi
fi

if [ -n "$OCF_RESKEY_pgport" ]; then
    export PGPORT=$OCF_RESKEY_pgport
fi

if [ -n "$OCF_RESKEY_pglibs" ]; then
    if [ -n "$LD_LIBRARY_PATH" ]; then
        export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$OCF_RESKEY_pglibs
    else
        export LD_LIBRARY_PATH=$OCF_RESKEY_pglibs
    fi
fi


# What kind of method was invoked?
case "$1" in
    status)     if pgsql_status
                then
                    ocf_log info "PostgreSQL is up"
                    exit $OCF_SUCCESS
                else
                    ocf_log info "PostgreSQL is down"
                    exit $OCF_NOT_RUNNING
                fi;;

    monitor)    pgsql_monitor
                exit $?;;

    start)      pgsql_start
                exit $?;;

    promote)    pgsql_promote
                exit $?;;

    demote)     pgsql_demote
                exit $?;;

    notify)     pgsql_notify
                exit $?;;

    stop)       pgsql_stop
                exit $?;;
    *)
                exit $OCF_ERR_UNIMPLEMENTED;;
esac
