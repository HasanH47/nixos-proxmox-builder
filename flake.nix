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

    # Alias default
    packages.x86_64-linux.default = self.packages.x86_64-linux.qcow2-image;
  };
}
