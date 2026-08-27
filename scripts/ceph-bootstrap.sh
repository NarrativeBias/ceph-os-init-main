#!/bin/bash

cephadm --image $(sudo podman images | grep ceph/ceph | awk '{ print $1":"$2}') bootstrap \
--skip-monitoring-stack \
--skip-dashboard \
--config ceph.conf.bootstrap \
--allow-fqdn-hostname \
--ssh-user cephorch \
--mon-ip $(ip r | grep src | grep bond0 | awk '{print $NF}') \
--cluster-network <!!!!!!!!!SET_IP/mask!!!!!!!!!!!> \
--log-to-file