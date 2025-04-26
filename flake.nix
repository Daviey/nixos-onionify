{
  description = "NixOS module for easily setting up Tor hidden services";

  inputs = { nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; };

  outputs = { self, nixpkgs }: {
    nixosModules.default = import ./module/tor-hidden-service.nix;

    nixosModules.torHiddenSites = self.nixosModules.default;

    # Example NixOS configuration
    nixosConfigurations.example = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.default
        ({ ... }: {
          services.torHiddenSites = {
            enable = true;
            sites = { "my-website" = { createDefaultSite = true; }; };
          };
        })
      ];
    };
  };
}
