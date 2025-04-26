{ config, pkgs, ... }:

{
  imports = [ ./module/tor-hidden-service.nix ];
}
