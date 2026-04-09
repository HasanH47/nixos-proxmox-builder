{ lib, pkgs, config, ... }:

let
  # Use a stable GPT PARTUUID so the image is bootable regardless of disk bus
  # (virtio/scsi/sata) by mounting via by-partuuid rather than /dev/vda1.
  rootPartUUID = "F222513B-DED1-49FA-B591-20CE86A2FE7F";
  rootPartUUIDPath = lib.toLower rootPartUUID;
in
{
  # ===========================================================
  # Universal QCOW2 (BIOS + UEFI) settings
  # (kernelParams / initrd / serial GRUB: lihat modules/boot-initrd-common.nix)
  # ===========================================================

  boot.loader = {
    systemd-boot.enable = lib.mkForce false;

    # GRUB for both legacy BIOS and UEFI in a single disk image.
    grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
      # Installed during image build where the disk is presented as /dev/vda.
      devices = [ "/dev/vda" ];
    };

    timeout = 1;
  };

  fileSystems."/" = lib.mkForce {
    # udev exposes partuuid paths in lowercase.
    device = "/dev/disk/by-partuuid/${rootPartUUIDPath}";
    autoResize = true;
    fsType = "ext4";
  };

  fileSystems."/boot" = lib.mkForce {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  # Produce a single disk that can boot on both BIOS and UEFI firmware.
  # We use `partitionTableType = "hybrid"` (GPT + BIOS GRUB partition + ESP).
  system.build.image = import (pkgs.path + "/nixos/lib/make-disk-image.nix") {
    inherit lib config pkgs;
    inherit (config.virtualisation) diskSize;
    baseName = "nixos-template";
    format = "qcow2";
    partitionTableType = "hybrid";

    # Make the root partition PARTUUID stable so mounting by PARTUUID works everywhere.
    rootGPUID = rootPartUUID;
    label = "nixos";
  };
}

