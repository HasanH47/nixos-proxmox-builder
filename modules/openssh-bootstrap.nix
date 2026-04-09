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
}
