{
  description = "NixOS 25.11 Proxmox VM Image Builder";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }: {
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

            boot.initrd.availableKernelModules = [
              "virtio_pci"
              "virtio_blk"
              "ext4"
            ];

            # Make early boot visible on serial console (useful for QEMU/Proxmox debugging).
            boot.kernelParams = [
              "console=tty0"
              "console=ttyS0,115200n8"
            ];

            boot.loader.grub = {
              extraConfig = ''
                serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
                terminal_input console serial
                terminal_output console serial
              '';
            };

            boot.loader.timeout = 1;
          })
        ];
      }).config.system.build.image;

    # Alias default
    packages.x86_64-linux.default = self.packages.x86_64-linux.qcow2-universal-image;
  };
}
