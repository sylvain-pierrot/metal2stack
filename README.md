# Metal2Stack

This repository provides a turnkey solution for fully automated deployment of OpenStack on bare metal or physical machines. From the operating system layer to the software layer, it leverages tools such as cloud-init, Metal as a Service (MaaS), Ansible, and Kolla-Ansible to ensure a seamless and efficient setup. This solution is designed to streamline the process, making it easy to provision and configure OpenStack.

## OS Specific

This project is specifically designed to support **Ubuntu Linux distributions**. Other operating systems are not within the scope of this project.

## Packages requierments

### Cargo

Install `just` using Cargo:

```bash
cargo install just
```

### Apt

Update your package list and install the required packages:

```bash
apt-get update
apt-get install fuseiso rsync xorriso dhcpdump
```

### Pip3

Install `Jinja2` using Pip3:

```bash
pip3 install Jinja2
```

## Getting started

```bash
just create-ubuntu-autoinstall-iso <ISO_FILE> <VALUES_FILE>

export SSH_PUBLIC_KEY=<sshkey>
just j2 templates/cloud-config.yml.j2 values.d/cpu011.yaml
```

## Troubleshooting 

### PXE (Pre-boot eXecution Environment)

PXE relies on two protocols:
- `DHCP` for getting an IP address, which  is necessary for the next step.
- `TFTP`, for serving the files for booting up.

`DHCP` not only gives an IP address, but also points to the TFTP server and the name of the first file for booting.

To see BOOTPREQUEST and BOOTPREPLY from `DHCP`, you can use:

```bash
dhcpdump -i <interface>
```