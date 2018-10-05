# -*- mode: ruby -*-
# vi: set ft=ruby :

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure("2") do |config|
  config.vm.box = "centos/6"

  config.vm.provider :libvirt do |lv|
    lv.cpus = 2
    lv.memory = 4096
    lv.volume_cache = :unsafe
  end

  config.vm.define "node1".to_sym do |node|
    node.vm.network :private_network, ip: "192.168.0.10"
    node.vm.network :private_network, ip: "192.168.10.10"
    node.vm.network :private_network, ip: "192.168.100.10"

    # node.vm.provision "shell", inline: <<-SHELL
    #     yum -y update
    # SHELL

    # Networking
    node.vm.provision "shell", inline: <<-SHELL
        hostname node1
        echo "192.168.0.10 node1" >> /etc/hosts
        echo "192.168.0.11 node2" >> /etc/hosts
        echo "192.168.10.10 node1-pg" >> /etc/hosts
        echo "192.168.10.11 node2-pg" >> /etc/hosts
        echo DONE setting up basic networking
    SHELL

    # Cluster tools
    node.vm.provision "shell", inline: <<-SHELL
        set -xe
        yum -y install pcs pacemaker cman fence-agents
        service pcsd start
        chkconfig pcsd on
        printf "hacluster\\nhacluster\\n" | passwd hacluster
        pcs cluster auth node{1,2} -u hacluster -p hacluster
        pcs cluster setup --name cfcluster node{1,2}
        pcs cluster start --all
        #sleep 1m
        pcs property set stonith-enabled=false
        pcs property set no-quorum-policy=ignore
        pcs resource defaults resource-stickiness="INFINITY"
        pcs resource defaults migration-threshold="1"
        pcs cluster status
        pcs status
        # pcs cluster enable --all node{1,2}
        echo DONE setting up cluster tools
    SHELL

    node.vm.provision "shell", inline: <<-SHELL
        # rpm -i /vagrant/cfengine-nova-hub-3.7.8-1.x86_64.rpm
        # cf-agent --bootstrap node1
        # service cfengine3 stop
        # chkconfig cfengine3 off
    SHELL
  end

  config.vm.define "node2".to_sym do |node|
    node.vm.network :private_network, ip: "192.168.0.11"
    node.vm.network :private_network, ip: "192.168.10.11"
    node.vm.network :private_network, ip: "192.168.100.11"

    # node.vm.provision "shell", inline: <<-SHELL
    #     yum -y update
    # SHELL

    node.vm.provision "shell", inline: <<-SHELL
        set -xe
        hostname node2
        echo "192.168.0.10 node1" >> /etc/hosts
        echo "192.168.0.11 node2" >> /etc/hosts
        echo "192.168.10.10 node1-pg" >> /etc/hosts
        echo "192.168.10.11 node2-pg" >> /etc/hosts
        echo DONE setting up basic networking
    SHELL

    # Cluster tools
    node.vm.provision "shell", inline: <<-SHELL
        set -xe
        yum -y install pcs pacemaker cman fence-agents
        service pcsd start
        chkconfig pcsd on
        printf "hacluster\\nhacluster\\n" | passwd hacluster
        echo DONE setting up cluster tools
    SHELL

    # Install cfengine
    node.vm.provision "shell", inline: <<-SHELL
        #rpm -i /vagrant/cfengine-nova-hub-3.7.8-1.x86_64.rpm
        #cf-agent --bootstrap node1
        #cf-agent --bootstrap node2
        #service cfengine3 stop
        #chkconfig cfengine3 off
    SHELL
  end
end
