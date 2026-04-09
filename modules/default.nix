{ ... }:

{
  imports = [
    ./image-profile.nix
    ./boot-initrd-common.nix
    ./common.nix
    ./cloud-init-proxmox.nix
    ./openssh-bootstrap.nix
    ./qemu-guest.nix
  ];
}
