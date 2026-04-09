# Shared early-boot stack for all VM images (virtio / SCSI / SATA paths).
{ lib, ... }:

{
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200n8"
  ];

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "scsi_mod"
    "ahci"
    "sd_mod"
    "sr_mod"
    "ext4"
  ];

  # Serial GRUB; image-specific modules may merge more `boot.loader.grub` options.
  boot.loader.grub.extraConfig = ''
    serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
    terminal_input console serial
    terminal_output console serial
  '';
}
