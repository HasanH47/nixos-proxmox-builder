{ lib, ... }:

let
  inherit (lib) mkOption types;
in
{
  options.image = {
    cloudInit = {
      strictNetwork = mkOption {
        type = types.bool;
        default = true;
        description = ''
          When cloud-init is enabled: force empty hostname and turn off global NixOS DHCP
          (same idea as nixpkgs `proxmox-image.nix`) so systemd-networkd is driven from NoCloud.
        '';
      };

      allowFallbackDhcp = mkOption {
        type = types.bool;
        default = false;
        description = ''
          When true (and cloud-init is enabled), do not force `networking.useDHCP = false`;
          use DHCP by default instead so a VM without a cloud-init ISO can still get an IP (labs only;
          can race with cloud-init on real Proxmox).
        '';
      };
    };

    ssh = {
      allowPasswordAuth = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Allow SSH password authentication (bootstrap user `nixos`).
          Set to false for stricter deployments after keys work.
        '';
      };
    };

    security = {
      sudoNopasswdForSudoGroup = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Grant `%sudo` passwordless sudo (Proxmox/cloud-init often places `ciuser` in `sudo`, not `wheel`).
        '';
      };
    };
  };
}
