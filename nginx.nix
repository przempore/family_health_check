{ pkgs ? import <nixpkgs> { }
}:

let
  # Define the Nginx configuration
  nginxConfig = pkgs.writeText "nginx.conf" ''
    user nobody nobody;
    error_log /dev/stdout info;
    pid /dev/null;
    
    events {
        # Required, even if empty
    }

    http {
      server {
          listen 20153 ssl; # Nginx listens on port 20153 for HTTPS
          server_name srv08.mikr.us;

          ssl_certificate /etc/nginx/ssl/fullchain.pem;
          ssl_certificate_key /etc/nginx/ssl/privkey.pem;

          ssl_protocols TLSv1.2 TLSv1.3;
          ssl_ciphers HIGH:!aNULL:!MD5;

          location / {
              proxy_pass http://backend-container:3000; # Proxy traffic to the backend on port 3000
              proxy_http_version 1.1;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection 'upgrade';
              proxy_set_header Host $host;
              proxy_cache_bypass $http_upgrade;
          }
      }
    }
  '';

  entrypoint = pkgs.writeScript "docker-entrypoint.sh" ''
    #!${pkgs.stdenv.shell}
    set -eux -o pipefail
    # Initialize /var
    mkdir -p /var/log/nginx /var/cache/nginx/client_body
    exec nginx -g "daemon off; error_log /dev/stderr debug;" -c /app/nginx.conf
  '';

  # Define the Docker image
  nginxImage = pkgs.dockerTools.buildImage {
    name = "nginx-container";
    tag = "latest";

    # Specify files to copy into the container
    copyToRoot = pkgs.buildEnv {
      name = "nginx-env";

      paths = [
        pkgs.nginx
        pkgs.dockerTools.fakeNss
        pkgs.coreutils

        # Generate self-signed certificates
        (pkgs.runCommand "ssl-certificates" { buildInputs = [ pkgs.openssl ]; } ''
          mkdir -p $out/etc/nginx/ssl
          openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout $out/etc/nginx/ssl/privkey.pem \
            -out $out/etc/nginx/ssl/fullchain.pem \
            -subj "/CN=localhost"
        '')
       (pkgs.runCommand "nginx-logs" { buildInputs = [ pkgs.coreutils ]; } ''
          mkdir -p $out/var/log/nginx
        '')
      ];
    };

    extraCommands = ''
      mkdir -p tmp/nginx_client_body

      # nginx still tries to read this directory even if error_log
      # directive is specifying another file :/
      # mkdir -p var/log/nginx

      mkdir -p app
      cp ${nginxConfig} app/nginx.conf
    '';

    # Ensure volumes are correctly configured
    config = {
      Cmd = [ entrypoint ];
      # Cmd = [
      #   "nginx"
      #   "-c"
      #   "/app/nginx.conf"
      # ];
      Volumes = {
        "/etc/nginx" = { };
      };
      ExposedPorts = {
        "20153/tcp" = { };
      };
    };

  };
in
nginxImage

