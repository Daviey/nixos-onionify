# nixos-onionify

A NixOS module for easily setting up Tor hidden services with nginx. Host your .onion sites on NixOS with minimal configuration.

## Features

- Simple declarative configuration for Tor hidden services
- Unix socket communication between Tor and nginx for better security
- Optional generation of default HTML/CSS templates
- Support for multiple onion sites
- Fully works with both traditional NixOS and flakes

## Usage

### Using with traditional configuration.nix

Import the module in your NixOS configuration:

```nix
{ config, pkgs, ... }:

{
  imports = [
    # ...
    (builtins.fetchGit {
      url = "https://github.com/Daviey/nixos-onionify.git";
      ref = "main";
      # Optional: pin to a specific commit for stability
      # rev = "the-commit-hash";
    })
  ];

  services.torHiddenSites = {
    enable = true;
    sites = {
      "my-website" = {
        createDefaultSite = true;
        # Optional: override defaults
        # webRoot = "/var/www/custom-path";
        # socketPath = "/run/nginx/custom-socket";
      };
    };
  };
}
```

### Using with flakes

Add to your `flake.nix` as an input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-onionify.url = "github:Daviey/nixos-onionify";
  };

  outputs = { self, nixpkgs, nixos-onionify, ... }: {
    nixosConfigurations.your-hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-onionify.nixosModules.default
        
        # Your configuration
        ({ ... }: {
          services.torHiddenSites = {
            enable = true;
            sites = {
              "my-website" = {
                createDefaultSite = true;
              };
            };
          };
        })
      ];
    };
  };
}
```

## Options

### Basic Options

- `services.torHiddenSites.enable` - Enable the Tor hidden sites service
- `services.torHiddenSites.sites.<name>.webRoot` - Directory containing website files (default: `/var/www/<name>`)
- `services.torHiddenSites.sites.<name>.socketPath` - Path to Unix socket for Tor-Nginx communication (default: `/run/nginx/<name>-socket`)
- `services.torHiddenSites.sites.<name>.createDefaultSite` - Whether to create default HTML/CSS files (default: `false`)

### Multiple Sites Example

You can easily configure multiple sites:

```nix
services.torHiddenSites = {
  enable = true;
  sites = {
    "personal-site" = {
      createDefaultSite = true;
    };
    "blog" = {
      createDefaultSite = false;
      webRoot = "/var/www/my-tor-blog";
    };
    "forum" = {
      webRoot = "/var/www/forum";
      socketPath = "/run/nginx/custom-forum-socket";
    };
  };
};
```

## Finding Your Onion Address

After applying the configuration, you can find your .onion address:

```bash
sudo cat /var/lib/tor/hidden_service/<site-name>/hostname
```

Access your site using the Tor Browser with this .onion address.

## Local Development

If you're developing the module locally:

### With configuration.nix
```nix
{ config, pkgs, ... }:

{
  imports = [
    # Path to your local copy
    /path/to/nixos-onionify
  ];
  
  # Your configuration...
}
```

### With flake.nix
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-onionify = {
      url = "path:/path/to/nixos-onionify";
      flake = false;
    };
  };
  
  # Your outputs...
}
```

## License

MIT
