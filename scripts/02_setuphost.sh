#!/usr/bin/env bash
set -xe

source utils/logging.sh
source utils/common.sh

# Generate user ssh key
if [ ! -f $HOME/.ssh/id_rsa.pub ]; then
    ssh-keygen -f ~/.ssh/id_rsa -P ""
fi

# root needs a private key to talk to libvirt
# See tripleo-quickstart-config/roles/virtbmc/tasks/configure-vbmc.yml
if sudo [ ! -f /root/.ssh/id_rsa_virt_power ]; then
  sudo ssh-keygen -f /root/.ssh/id_rsa_virt_power -P ""
  sudo cat /root/.ssh/id_rsa_virt_power.pub | sudo tee -a /root/.ssh/authorized_keys
fi

# required for ansible playbook (TODO put in ansible)
sudo mkdir -p /etc/qemu
sudo touch /etc/qemu/bridge.conf

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "working_dir=$WORKING_DIR" \
    -e "num_masters=$NUM_MASTERS" \
    -e "num_workers=$NUM_WORKERS" \
    -e "extradisks=$VM_EXTRADISKS" \
    -e "virthost=$HOSTNAME" \
    -e "platform=$NODES_PLATFORM" \
    -e "manage_baremetal=$MANAGE_BR_BRIDGE" \
    -i vm-setup/inventory.ini \
    -b -vvv vm-setup/setup-playbook.yml

# Allow local non-root-user access to libvirt
# Restart libvirtd service to get the new group membership loaded
if  id $USER | grep -q libvirt; then
  sudo usermod -a -G "libvirtd" $USER
  sudo systemctl restart libvirtd
fi

# Usually virt-manager/virt-install creates this: https://www.redhat.com/archives/libvir-list/2008-August/msg00179.html
if ! virsh pool-uuid default > /dev/null 2>&1 ; then
    virsh pool-define /dev/stdin <<EOF
<pool type='dir'>
  <name>default</name>
  <target>
    <path>/var/lib/libvirt/images</path>
  </target>
</pool>
EOF
    virsh pool-start default
    virsh pool-autostart default
fi

if [ "$MANAGE_PRO_BRIDGE" == "y" ]; then
    # Adding an IP address in the libvirt definition for this network results in
    # dnsmasq being run, we don't want that as we have our own dnsmasq, so set
    # the IP address here
    if [ ! - /etc/network/interfaces.d/provisioning.cfg ] ; then
    cat <<EOF>/tmp/bridge
auto provisioning
iface provisioning inet static
        address 172.22.0.1
        network 255.255.255.0
        bridge_ports $PRO_IF
        bridge_stp off
        bridge_fd 0
        bridge_maxwait 0
EOF
    sudo mv /tmp/bridge /etc/network/interfaces.d/provisioning.cfg
    fi
    sudo ifdown provisioning || true
    sudo ifup provisioning

if [ "$MANAGE_INT_BRIDGE" == "y" ]; then
    # Create the baremetal bridge
    if [ ! -e /etc/network/interfaces.d/baremetal.cfg ] ; then
    cat <<EOF>/tmp/bridge
auto baremetal
iface baremetal inet static
        bridge_ports $INT_IF
        bridge_stp off
        bridge_fd 0
        bridge_maxwait 0
EOF
    sudo mv /tmp/bridge /etc/network/interfaces.d/baremetal.cfg
    fi
    sudo ifdown baremetal || true
    sudo ifup baremetal

    fi
fi

# restart the libvirt network so it applies an ip to the bridge
if [ "$MANAGE_BR_BRIDGE" == "y" ] ; then
    sudo virsh net-destroy baremetal
    sudo virsh net-start baremetal
    if [ "$INT_IF" ]; then #Need to bring UP the NIC after destroying the libvirt network
        sudo ifup $INT_IF
    fi
fi
