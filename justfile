@default:
  just --list

j2 TEMPLATE_FILE VALUES_FILE:
  #!/usr/bin/python3

  import jinja2
  import yaml
  import os

  def getenv(key):
    return os.getenv(key)

  def include_sub_template(template_file, values, env):
    template = env.get_template(template_file)
    return template.render(values)

  if __name__ == "__main__":
    template_file = "{{TEMPLATE_FILE}}"
    values_file = "{{VALUES_FILE}}"

    with open(values_file) as main_values_file:
        main_values = yaml.safe_load(main_values_file)
        
    env = jinja2.Environment(loader=jinja2.FileSystemLoader(searchpath="."))
    env.globals['include_sub_template'] = lambda sub_template_file, sub_values: include_sub_template(sub_template_file, sub_values, env)
    env.globals['getenv'] = lambda key: getenv(key)

    main_template = env.get_template(template_file)
    print(main_template.render(main_values))

check-j2 TEMPLATE_FILE VALUES_FILE:
  just j2 {{TEMPLATE_FILE}} {{VALUES_FILE}} | cloud-init schema --config-file /dev/stdin

# create-<distro>-autoinstall-iso
create-ubuntu-autoinstall-iso ISO_FILE VALUES_FILE:
  #!/usr/bin/env bash

  set -euo pipefail

  VALUES_FILE="{{VALUES_FILE}}"
  ISO_FILE="{{ISO_FILE}}"
  TMP_DIR=".build"
  CUSTOM_ISO_DIR="custom_iso"
  MOUNT_POINT="/mnt/mounted_iso"
  VOLUME_ID="Ubuntu 22.04.4 LTS amd64"

  cleanup() {
    sudo rm -rf "$TMP_DIR/"
    sudo umount "$MOUNT_POINT" || true
  }
  trap cleanup EXIT

  for var in ISO_FILE VALUES_FILE; do
    if [ -z "${!var}" ]; then
      echo "$var variable is not set. Please set the path to the appropriate file."
      exit 1
    fi
    if [ ! -f "${!var}" ]; then
      echo "File not found at ${!var}!"
      exit 1
    fi
  done
  
  HOSTNAME=$(cat $VALUES_FILE | grep hostname | awk '{ print $2}')
  ISO_OUTPUT="ubuntu-22.04.4-autoinstall-live-server-amd64-$HOSTNAME.iso"

  just check-j2 ./templates/cloud-config.yml.j2 "$VALUES_FILE"

  mkdir -p "$TMP_DIR"
  sudo fuseiso -p "$ISO_FILE" "$MOUNT_POINT"
  sudo rsync -ra "$MOUNT_POINT/" "$TMP_DIR/$CUSTOM_ISO_DIR" --delete
  sudo chmod -R +w "$TMP_DIR/$CUSTOM_ISO_DIR"

  ######### Customize ISO Here ###########

  sudo mkdir -p "$TMP_DIR/$CUSTOM_ISO_DIR/preseed"
  just j2 ./templates/cloud-config.yml.j2 "$VALUES_FILE" | sudo tee "$TMP_DIR/$CUSTOM_ISO_DIR/preseed/user-data" > /dev/null
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