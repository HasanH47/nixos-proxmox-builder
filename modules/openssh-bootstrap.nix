{ config, lib, ... }:

let
  cfg = config.image;
in
{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = cfg.ssh.allowPasswordAuth;
      KbdInteractiveAuthentication = cfg.ssh.allowPasswordAuth;
    };
  };

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "sudo" ];
    initialPassword = "nixos";
    # openssh.authorizedKeys.keys = [
    #   "ssh-ed25519 AAAAC3Nza... user@host"
    # ];
  };
}
