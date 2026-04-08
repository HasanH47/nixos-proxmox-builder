{ lib, ... }:

{
  # ===========================================================
  # Proxmox VM Settings (hanya untuk output VMA Proxmox)
  # ===========================================================
  proxmox = {
    qemuConf = {
      # Nama VM yang muncul di Proxmox
      name = "nixos-template";

      # Spek default VM (bisa diubah di Proxmox setelah import)
      cores = 2;
      memory = 2048; # MB

      # BIOS: "seabios" (legacy) atau "ovmf" (UEFI)
      bios = "seabios";

      # Network interface
      net0 = "virtio=00:00:00:00:00:00,bridge=vmbr0";
    };

    # Aktifkan cloud-init supaya bisa set IP/hostname/SSH key dari Proxmox UI
    cloudInit.enable = true;
  };
}

