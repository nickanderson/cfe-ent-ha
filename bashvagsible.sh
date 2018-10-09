#!/bin/bash

set -o pipefail

SSH="ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

function get_nodes() {
    vagrant status | sed -r -e '/running/!d' -e 's/^([-a-zA-Z_0-9.]+).*/\1/'
}

function get_node_keyfile() {
    # $1 -- node name
    echo ".vagrant/machines/$1/libvirt/private_key"
}

function get_node_ip () {
    # $1 -- node name
    read id < .vagrant/machines/$1/libvirt/id
    sudo virsh domifaddr $id | sed -r -e '/ipv4/!d' -e 's/.*\s+ipv4\s+([0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}).*/\1/'
}

function run_all_serial() {
    # $@ -- shell command to execute on nodes
    for node in `get_nodes`; do
        echo "+$node: $@"
        $SSH -i `get_node_keyfile $node` "vagrant@`get_node_ip $node`" "sudo $@"
        # echo "Done: $1" >&2
    done
}

function run_all_parallel() {
    # $@ -- shell command to execute on nodes
    export -f get_node_keyfile
    export -f get_node_ip
    export SSH
    export RUN_CMD="sudo bash -c '$@'"
    get_nodes | parallel --tagstring "{}:" '$SSH -i `get_node_keyfile {}` "vagrant@`get_node_ip {}`" "$RUN_CMD"'
}

function run_on() {
    # $1 -- node name
    # shift; $@ -- shell command to execute on the node

    node=$1
    shift
    echo "+$node: sudo bash -c '$@'"
    $SSH -i `get_node_keyfile $node` "vagrant@`get_node_ip $node`" "sudo bash -c '$@'"
    # echo "Done: $1" >&2
}

function run_on_silent() {
    # $1 -- node name
    # shift; $@ -- shell command to execute on the node

    node=$1
    shift
    $SSH -i `get_node_keyfile $node` "vagrant@`get_node_ip $node`" "sudo bash -c '$@'"
}
