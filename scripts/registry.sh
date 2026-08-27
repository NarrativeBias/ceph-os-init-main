#!/bin/bash
REGISTRY="$(hostname -f):5000"
REPLACE="$(hostname -s):5000"

for image in *.tar.gz; do
  sudo podman load -i "$image"
done

sudo podman run -d --net host -v registry:/var/lib/registry --name registry docker.io/library/registry:2
sudo podman generate systemd --files --new --name registry
sudo cp container-registry.service /etc/systemd/system
sudo sed -i "s/$REPLACE/$REGISTRY/g"/etc/containers/registries.conf
sudo sed -i "s/$REPLACE/$REGISTRY/g" /etc/containers/registries.conf.d/ceph.conf
sudo systemctl enable container-registry.service --now

for image in $(sudo podman image ls -n --format "table {{.Repository}}:{{.Tag}}" | grep -v registry | grep ""); do
  repo_prefix=$(echo "$image" | cut -d '/' -f 1)
  repo_suffix=$(echo "$image" | cut -d '/' -f 2-)
  new_image="${REGISTRY}/${repo_suffix}"
  sudo podman tag "$image" "$new_image"
  sudo podman image rm "$image"
  sudo podman push "$new_image"
  sudo podman image rm "$new_image"
  sudo podman image pull "$new_image"
done

