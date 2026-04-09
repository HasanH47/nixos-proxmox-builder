{ config, lib, ... }:

let
  cfg = config.image;
  ciOn = config.services.cloud-init.enable;
in
{
  services.cloud-init = {
    enable = true;
    network.enable = true;
    settings = {
      datasource_list = [ "NoCloud" "ConfigDrive" "None" ];
    };
  };

  networking = lib.mkMerge [
    (lib.mkIf (ciOn && cfg.cloudInit.strictNetwork && !cfg.cloudInit.allowFallbackDhcp) {
      hostName = lib.mkForce "";
      useDHCP = lib.mkForce false;
    })
    (lib.mkIf (ciOn && (!cfg.cloudInit.strictNetwork || cfg.cloudInit.allowFallbackDhcp)) {
      hostName = lib.mkForce "";
      useDHCP = lib.mkDefault true;
    })
  ];

  users.groups.sudo = { };

  security.sudo.wheelNeedsPassword = false;
  security.sudo.extraConfig = lib.mkIf cfg.security.sudoNopasswdForSudoGroup ''
    %sudo ALL=(ALL) NOPASSWD: ALL
  '';
}
