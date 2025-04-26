# /etc/nixos/modules/tor-hidden-sites.nix
#
# NixOS module to easily configure Tor hidden services backed by Nginx.
# It sets up Tor onion services, Nginx virtual hosts listening on Unix sockets,
# required directories, and optionally creates default placeholder web content.

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.torHiddenSites;

  # Helper function to consistently generate the data directory path
  mkHiddenServiceDataDir = name: "/var/lib/tor/hidden_services/${name}";

  # Type definition for a single hidden site configuration.
  # The 'name' of the site is implicitly the attribute key used in `cfg.sites`.
  siteOpts = { name, config, ... }: {
    options = {
      webRoot = mkOption {
        type = types.path; # Use types.path for directory paths
        default = "/var/www/${name}";
        description =
          "Directory containing the website files for this hidden service.";
        example = "/srv/http/my-onion";
      };

      socketPath = mkOption {
        type = types.path; # Use types.path for socket paths
        # Use a consistent naming scheme based on the site name.
        default = "/run/nginx/sockets/${name}.sock";
        description =
          "Path to the Unix domain socket for communication between Tor and Nginx.";
        example = "/run/nginx/sockets/my-site.sock";
      };

      createDefaultSite = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to automatically create basic index.html and styles.css
          placeholder files in the `webRoot` if they don't already exist.
          Useful for quick setup and testing.
        '';
      };
    };
  };

in {
  # Interface definition for this module
  options.services.torHiddenSites = {
    enable = mkEnableOption "Tor hidden sites backed by Nginx";

    sites = mkOption {
      type = types.attrsOf (types.submodule siteOpts);
      default = { };
      description = "Attribute set defining the Tor hidden sites to configure.";
      example = literalExpression ''
        {
          # A simple site using defaults and creating placeholder content
          "my-first-site" = {
            createDefaultSite = true;
          };

          # A site with a custom web root, not creating default files
          "secure-project" = {
            webRoot = "/opt/secure-web";
            # socketPath defaults to /run/nginx/sockets/secure-project.sock
            createDefaultSite = false; # Or simply omit this line
          };
        }
      '';
    };
  };

  # Implementation of the module
  config = mkIf cfg.enable {

    # 1. Ensure Tor service is enabled and configure Onion Services
    services.tor = {
      enable = true;
      # Client mode is needed for the Tor daemon to function and connect.
      client.enable = true;

      # Define the hidden services (v3 Onion Services)
      relay.onionServices = mapAttrs (name: site: {
        version = 3; # Use the current standard v3 onion services
        # Map the virtual port 80 (standard HTTP) to the Nginx Unix socket
        map = [{
          port = 80; # The port users access the service on via Tor Browser
          target = {
            unix = site.socketPath; # The Unix socket path
          };
        }];
      }) cfg.sites;
    };

    # 2. Ensure Nginx service is enabled and configure Virtual Hosts
    services.nginx = {
      enable = true;
      # Define a virtual host for each hidden site
      virtualHosts = mapAttrs (name: site: {
        # Make Nginx listen on the specific Unix socket for this site.
        listen = [{
          addr = "unix:${site.socketPath}";
          ssl = false;
        }];
        # Set the document root for this virtual host.
        root = site.webRoot;
        # Add some basic recommended Nginx configurations.
        extraConfig = ''
          index index.html index.htm;
          add_header X-Frame-Options "SAMEORIGIN" always;
          add_header X-Content-Type-Options "nosniff" always;
          add_header Referrer-Policy "no-referrer" always;
          location ~ /\. { deny all; log_not_found off; access_log off; }
        '';
      }) cfg.sites;
    };

    # 3. Create necessary directories and set permissions using systemd-tmpfiles
    systemd.tmpfiles.rules =
      # Ensure the parent directory for Nginx sockets exists with correct ownership.
      [
        "d /run/nginx/sockets 0755 ${config.services.nginx.user} ${config.services.nginx.group} -"
      ] ++
      # Create data directories for each Tor hidden service with restrictive permissions.
      (mapAttrsToList (name: site:
        # Use the helper function to construct the path. <<< CHANGED
        "d ${
          mkHiddenServiceDataDir name
        } 0700 ${config.users.users.tor.name} ${config.users.groups.tor.name} -")
        cfg.sites) ++
      # Create web root directories for each site if they don't exist, and ensure permissions.
      (lib.flatten (mapAttrsToList (name: site: [
        "L+ ${site.webRoot} - - - - -"
        "Z ${site.webRoot} 0755 ${config.services.nginx.user} ${config.services.nginx.group} -"
      ]) cfg.sites));

    # 4. Ensure required packages are installed
    environment.systemPackages = [ pkgs.tor pkgs.nginx ];

    # 5. Create default website files using an activation script if requested.
    system.activationScripts = mapAttrs' (name: site:
      nameValuePair "setupTorSite-${name}" {
        text = ''
          # Wrap everything in a function to allow local variables
          function setup_tor_site_${name}() {
            local nginx_user="${config.services.nginx.user}"
            local nginx_group="${config.services.nginx.group}"
            # Use the helper function to construct the path
            local tor_data_dir="${mkHiddenServiceDataDir name}"

            echo "--> Activation script for Tor hidden site: ${name}"
            echo "    Ensuring directory ${site.webRoot} exists..."
            mkdir -p "${site.webRoot}"
            echo "    Setting ownership for ${site.webRoot} to $nginx_user:$nginx_group..."
            chown -R "$nginx_user:$nginx_group" "${site.webRoot}"
            echo "    Setting permissions for ${site.webRoot} (dirs 755, files 644)..."
            chmod -R u=rwX,g=rX,o=rX "${site.webRoot}"

            ${
              lib.optionalString site.createDefaultSite ''
                            echo "    'createDefaultSite' is true, checking/creating default files..."
                            local index_file="${site.webRoot}/index.html"
                            local css_file="${site.webRoot}/styles.css"

                            # Create index.html if it doesn't exist
                            if [ ! -f "$index_file" ]; then
                              echo "    Creating default $index_file..."
                              cat > "$index_file" << EOF
                <!DOCTYPE html>
                <html lang="en">
                <head>
                    <meta charset="UTF-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <title>Tor Hidden Service: ${name}</title>
                    <link rel="stylesheet" href="styles.css">
                </head>
                <body>
                    <div class="container">
                        <header> <h1>Welcome to My Onion Site (${name})</h1> <p class="tagline">Running on NixOS through the Tor network</p> </header>
                        <main>
                            <section class="about"> <h2>About This Site</h2> <p>This is a private website hosted as a Tor hidden service (${name}).</p> <p>The content is only accessible through the Tor network using the .onion address associated with this service.</p> <p>Find the address in <code>$tor_data_dir/hostname</code> after Tor starts.</p> </section>
                            <section class="info"> <h2>What is Tor?</h2> <p>Tor (The Onion Router) is free and open-source software enabling anonymous communication. It directs Internet traffic through a volunteer overlay network to conceal location and usage.</p> </section>
                        </main>
                        <footer> <p>© $(date +%Y) - ${name} Onion Site</p> </footer>
                    </div>
                </body>
                </html>
                EOF
                              chown "$nginx_user:$nginx_group" "$index_file"
                              chmod 644 "$index_file"
                            else
                              echo "    $index_file already exists, skipping creation."
                            fi

                            # Create styles.css if it doesn't exist
                            if [ ! -f "$css_file" ]; then
                              echo "    Creating default $css_file..."
                              cat > "$css_file" << 'EOF'
                /* Basic Reset & Dark Theme Styles */
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body { font-family: 'Courier New', Courier, monospace; line-height: 1.6; color: #c0c0c0; background-color: #121212; padding: 20px; }
                .container { max-width: 800px; margin: 20px auto; background-color: #1e1e1e; padding: 30px; border: 1px solid #333; border-radius: 8px; box-shadow: 0 0 15px rgba(0, 0, 0, 0.5); }
                header { text-align: center; margin-bottom: 40px; border-bottom: 1px solid #444; padding-bottom: 20px; }
                h1 { color: #bb86fc; font-size: 2em; margin-bottom: 10px; word-wrap: break-word; }
                .tagline { color: #888; font-style: italic; }
                main { margin-bottom: 30px; }
                section { margin-bottom: 30px; padding: 20px; background-color: #252525; border-radius: 6px; border: 1px solid #3a3a3a; }
                h2 { color: #03dac6; margin-bottom: 15px; border-bottom: 1px dotted #555; padding-bottom: 5px; }
                p { margin-bottom: 15px; }
                code { background-color: #2c2c2c; padding: 2px 5px; border-radius: 3px; font-size: 0.9em; }
                strong { color: #cf6679; }
                footer { text-align: center; font-size: 0.9em; color: #666; border-top: 1px solid #444; padding-top: 20px; margin-top: 30px; }
                @media screen and (max-width: 600px) { .container { padding: 15px; margin: 10px; } h1 { font-size: 1.5em; } section { padding: 15px; } body { padding: 10px; } }
                EOF
                              chown "$nginx_user:$nginx_group" "$css_file"
                              chmod 644 "$css_file"
                            else
                              echo "    $css_file already exists, skipping creation."
                            fi
              ''
            } # End optionalString for createDefaultSite
            echo "<-- Finished activation script for ${name}"
          }

          # Call the function
          setup_tor_site_${name}
        ''; # End text block for the activation script
        deps = [ "users" "groups" ];
      }) cfg.sites;

    # 6. Security Considerations (Informational - enforced above)
    # - Tor data directories (`/var/lib/tor/hidden_services/*`) should be 0700 owned by tor:tor. (Handled by tmpfiles)
    # - Nginx web root (`/var/www/*` or custom) should be readable by nginx user/group (e.g., 755/644). (Handled by tmpfiles/activation script)
    # - Nginx socket directory (`/run/nginx/sockets`) needs correct permissions for Nginx to create sockets. (Handled by tmpfiles)
    # - Firewall: No incoming ports need to be opened on the host firewall for the hidden service itself,
    #   as connections happen *from* Tor to the local Nginx socket.

  }; # End mkIf cfg.enable
}
