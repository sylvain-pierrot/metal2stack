set dotenv-load

ssh_public_key := env_var('SSH_PUBLIC_KEY')

@default:
  just --list

generate-supervisor-cloud-config:
  #!/usr/bin/python3

  import jinja2
  import yaml
  import os

  def include_sub_template(template_file, values, env):
    template = env.get_template(template_file)
    return template.render(values)

  if __name__ == "__main__":
    ssh_public_key = "{{ssh_public_key}}"
    template_file = "templates/cloud-config/supervisor.yml.j2"
    supervisor_values_file = "values.d/supervisor.yml"
    nodes_values_file = "values.d/nodes.yml"

    with open(supervisor_values_file) as f1, open(nodes_values_file) as f2:
      supervisor = yaml.safe_load(f1)
      nodes = yaml.safe_load(f2)
        
    env = jinja2.Environment(loader=jinja2.FileSystemLoader(searchpath="."))
    env.globals['include_sub_template'] = lambda sub_template_file, sub_values: include_sub_template(sub_template_file, sub_values, env)
    env.globals['getenv'] = lambda key: os.getenv(key)

    template = env.get_template(template_file)
    print(template.render(supervisor,nodes=nodes))

generate-node-cloud-config HOSTNAME:
  #!/usr/bin/python3

  import jinja2
  import yaml
  import os
  import sys
  
  def get_node_by_hostname(hostname, nodes):
    for node in nodes:
        if node['hostname'] == hostname:
            return node
    return None

  if __name__ == "__main__":
    ssh_public_key = "{{ssh_public_key}}"
    hostname = "{{HOSTNAME}}"
    template_file = "templates/cloud-config/node.yml.j2"
    values_file = "values.d/nodes.yml"

    with open(values_file) as f:
      nodes = yaml.safe_load(f)
      node = get_node_by_hostname(hostname, nodes)

      if node is None:
        print(f"Error: Hostname '{hostname}' not found in machines list.")
        sys.exit(1)

    env = jinja2.Environment(loader=jinja2.FileSystemLoader(searchpath="."))
    env.globals['getenv'] = lambda key: os.getenv(key)

    template = env.get_template(template_file)
    print(template.render(node))

check-supervisor-cloud-config:
  just generate-supervisor-cloud-config | cloud-init schema --config-file /dev/stdin

check-node-cloud-config HOSTNAME:
  just generate-node-cloud-config {{HOSTNAME}} | cloud-init schema --config-file /dev/stdin

generate-supervisor-iso ISO_FILE:
  #!/usr/bin/env bash

  set -euo pipefail

  ISO_FILE="{{ISO_FILE}}"
  TMP_DIR=".build"
  CUSTOM_ISO_DIR="custom_iso"
  MOUNT_POINT="/mnt/mounted_iso"
  VOLUME_ID="Ubuntu 22.04.4 LTS amd64"
  ISO_OUTPUT="supervisor.iso"

  cleanup() {
    sudo rm -rf "$TMP_DIR/"
    sudo umount "$MOUNT_POINT" || true
  }
  trap cleanup EXIT

  if [ -z "${ISO_FILE}" ]; then
      echo "ISO_FILE variable is not set. Please set the path to the appropriate file."
      exit 1
  fi
  if [ ! -f "${ISO_FILE}" ]; then
      echo "File not found at ${ISO_FILE}!"
      exit 1
  fi

  just check-supervisor-cloud-config

  mkdir -p "$TMP_DIR"
  sudo fuseiso -p "$ISO_FILE" "$MOUNT_POINT"
  sudo rsync -ra "$MOUNT_POINT/" "$TMP_DIR/$CUSTOM_ISO_DIR" --delete
  sudo chmod -R +w "$TMP_DIR/$CUSTOM_ISO_DIR"

  ######### Customize ISO Here ###########

  sudo mkdir -p "$TMP_DIR/$CUSTOM_ISO_DIR/preseed"
  just generate-supervisor-cloud-config | sudo tee "$TMP_DIR/$CUSTOM_ISO_DIR/preseed/user-data" > /dev/null
  sudo touch "$TMP_DIR/$CUSTOM_ISO_DIR/preseed/meta-data"
  
  sudo sed -i -e '0,/---/s,30,3,g' "$TMP_DIR/$CUSTOM_ISO_DIR/boot/grub/grub.cfg" 
  sudo sed -i -e '0,/---/s,---, autoinstall ds=nocloud\\\;s=/cdrom/preseed/ ---,g' "$TMP_DIR/$CUSTOM_ISO_DIR/boot/grub/grub.cfg"
  sudo sed -i -e '0,/---/s,---, autoinstall ds=nocloud\\\;s=/cdrom/preseed/ ---,g' "$TMP_DIR/$CUSTOM_ISO_DIR/boot/grub/loopback.cfg"
  
  ######### End Customizations ###########

  PARTITION_INFO=$(fdisk -l "$ISO_FILE" | grep "^$ISO_FILE" | awk '{print $2, $4}')
  read -r EFI_START EFI_SECTORS <<< $(echo "$PARTITION_INFO" | awk 'NR==2 {print $1, $2}')
  
  dd if="$ISO_FILE" bs=1 count=432 of="$TMP_DIR/boot_hybrid.img"
  dd if="$ISO_FILE" bs=512 skip="${EFI_START}" count="${EFI_SECTORS}" of="$TMP_DIR/efi.img"

  xorriso -as mkisofs -r \
    -V "$VOLUME_ID" \
    -o "$ISO_OUTPUT" \
    --grub2-mbr "$TMP_DIR/boot_hybrid.img" \
    -partition_offset 16 \
    --mbr-force-bootable \
    -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b "$TMP_DIR/efi.img" \
    -appended_part_as_gpt \
    -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
    -c '/boot.catalog' \
    -b '/boot/grub/i386-pc/eltorito.img' \
    -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
    -eltorito-alt-boot \
    -e '--interval:appended_partition_2:::' \
    -no-emul-boot \
    "$TMP_DIR/$CUSTOM_ISO_DIR"