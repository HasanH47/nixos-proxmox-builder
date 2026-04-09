{
  description = "NixOS 25.11 Proxmox VM Image Builder";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }: let
    inherit (nixpkgs) lib;
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    # Eval cepat: gabung modul image tanpa build disk/kernel penuh sampai ada yang akses toplevel.
    checkSystem = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        ({ lib, ... }: {
          boot.loader.grub.enable = lib.mkForce false;
          boot.loader.systemd-boot.enable = lib.mkForce false;
          fileSystems."/" = lib.mkForce {
            device = "/dev/vda1";
            fsType = "ext4";
          };
        })
      ];
    };
  in {
    checks.x86_64-linux.nixos-config =
      pkgs.writeText "stateVersion" checkSystem.config.system.stateVersion;

    packages.x86_64-linux.proxmox-image =
      (nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          ./proxmox.nix
          ({ modulesPath, ... }: {
            imports = [
              (modulesPath + "/virtualisation/proxmox-image.nix")
            ];
          })
        ];
      }).config.system.build.VMA;

    # Universal QCOW2: single disk that boots on BIOS and UEFI.
    packages.x86_64-linux.qcow2-universal-image =
      (nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          ./universal-qcow2.nix
        ];
      }).config.system.build.image;

    # Generic QCOW2 image (for sysadmin/import workflows).
    packages.x86_64-linux.qcow2-image =
      (nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          ({ modulesPath, ... }: {
            imports = [
              (modulesPath + "/virtualisation/disk-image.nix")
            ];

            image = {
              format = "qcow2";
              baseName = "nixos-template";
            };
          })
        ];
      }).config.system.build.image;

    # QCOW2 image that boots with legacy BIOS (SeaBIOS).
    packages.x86_64-linux.qcow2-bios-image =
      (nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          ({ modulesPath, lib, ... }: {
            imports = [
              (modulesPath + "/virtualisation/disk-image.nix")
            ];

            image = {
              format = "qcow2";
              baseName = "nixos-template";
              efiSupport = false;
            };

            # Some hypervisors/firmware combos don't reliably create /dev/disk/by-label/* early
            # in initrd. Use the explicit device path for legacy BIOS images.
            fileSystems."/" = lib.mkForce {
              device = "/dev/vda1";
              fsType = "ext4";
            };

            boot.loader.timeout = 1;
          })
        ];
      }).config.system.build.image;

    # Alias default
    packages.x86_64-linux.default = self.packages.x86_64-linux.qcow2-universal-image;
  };
}
