{ config, pkgs, modulesPath, lib, ... }:

{
  # Ukuran disk image.
  # Catatan: modul image builder di nixpkgs memakai satuan MiB (bukan "20G" string).
  # 20 GiB = 20480 MiB
  virtualisation.diskSize = 20480;

  # ===========================================================
  # Network - wajib untuk cloud-init
  # ===========================================================
  systemd.network.enable = true;
  networking = {
    useDHCP          = lib.mkDefault true;
    firewall.enable  = true;
    firewall.allowedTCPPorts = [ 22 ];
  };

  # ===========================================================
  # SSH
  # ===========================================================
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin    = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # ===========================================================
  # User
  # GANTI bagian authorizedKeys.keys dengan SSH public key kamu!
  # ===========================================================
  users.users.nixos = {
    isNormalUser = true;
    extraGroups  = [ "wheel" ];
    # openssh.authorizedKeys.keys = [
      # Contoh: "ssh-ed25519 AAAAC3Nza... user@host"
      # Tambahkan SSH public key kamu di sini
    # ];
  };

  # Izinkan sudo tanpa password untuk wheel group
  security.sudo.wheelNeedsPassword = false;

  # ===========================================================
  # Nix settings
  # ===========================================================
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users          = [ "root" "@wheel" ];
    # Izinkan rebuild remote
    auto-optimise-store    = true;
  };

  # Garbage collect otomatis
  nix.gc = {
    automatic  = true;
    dates      = "weekly";
    options    = "--delete-older-than 7d";
  };

  # ===========================================================
  # Packages dasar
  # ===========================================================
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    jq
  ];

  # ===========================================================
  # Cloud-init & QEMU guest agent
  # ===========================================================
  services.cloud-init = {
    enable = true;
    network.enable = true;
  };

  services.qemuGuest.enable = true;

  # ===========================================================
  # Timezone (ganti sesuai kebutuhan)
  # ===========================================================
  time.timeZone = "Asia/Jakarta";

  # ===========================================================
  # Locale
  # ===========================================================
  i18n.defaultLocale = "en_US.UTF-8";

  # ===========================================================
  # State version - jangan diubah setelah install!
  # ===========================================================
  system.stateVersion = "25.11";
}
