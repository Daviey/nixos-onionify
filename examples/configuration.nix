{ config, pkgs, ... }:

{
  imports = [
    # Import the module directly
    ../module/tor-hidden-service.nix

    # Or you can import from github
    # (builtins.fetchGit {
    #   url = "https://github.com/Daviey/nixos-onionify.git";
    #   ref = "main";
    # })
  ];

  # Configure Tor hidden sites
  services.torHiddenSites = {
    enable = true;
    sites = {
      "my-website" = { createDefaultSite = true; };

      "blog" = {
        createDefaultSite = false;
        webRoot = "/var/www/blog";
      };
    };
  };
}
