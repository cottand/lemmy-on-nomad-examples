variable "lemmy_version" {
  type    = string
  default = "0.18.0"
}
variable "instance_name" {
  type    = string
  default = "your.url.here.com"
}

job "lemmy" {
  datacenters = ["dc1"]
  type        = "service"
  group "proxy" {
    network {
      mode = "bridge"
      port "http" { to = 80 }
    }

    task "lemmy-proxy" {
      service {
        name     = "lemmy-proxy"
        provider = "nomad"
        port     = "http"
        check {
          name     = "alive"
          type     = "tcp"
          interval = "20s"
          timeout  = "2s"
          check_restart {
            limit           = 3
            grace           = "10s"
            ignore_warnings = false
          }
        }
      }

      driver = "docker"

      config {
        image = "nginx:alpine3.17-slim"
        ports = ["http"]
        volumes = [
          "local/nginx.conf:/etc/nginx/nginx.conf",
        ]
      }

      template {
        destination = "local/nginx.conf"
        change_mode = "restart"
        data        = <<EOF
worker_processes 1;
events {
    worker_connections 1024;
}

http {
    upstream lemmy {
        {{ range nomadService "lemmy" }}
        server "{{ .Address }}:{{ .Port }}";
        {{ else }}server 127.0.0.1:65535; # force a 502
        {{ end }}
    }
    upstream lemmy-ui {
        {{ range nomadService "lemmy-ui" }}
        server "{{ .Address }}:{{ .Port }}";
        {{ else }}server 127.0.0.1:65535; # force a 502
        {{ end }}
    }

    server {
        # this is the port inside docker, not the public one yet
        listen 80;
        # change if needed, this is facing the public web
        server_name ${var.instance_name};
        server_tokens off;

        gzip on;
        gzip_types text/css application/javascript image/svg+xml;
        gzip_vary on;

        # Upload limit, relevant for pictrs
        client_max_body_size 20M;

        add_header X-Frame-Options SAMEORIGIN;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";

        # frontend general requests
        location / {

            # distinguish between ui requests and backend
            # don't change lemmy-ui or lemmy here, they refer to the upstream definitions on top
            set $proxpass "http://lemmy-ui";

            if ($http_accept ~ "^application/.*$") {
              set $proxpass "http://lemmy";
            }
            if ($request_method = POST) {
              set $proxpass "http://lemmy";
            }
            proxy_pass $proxpass;

            rewrite ^(.+)/+$ $1 permanent;
            # Send actual client IP upstream
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }

        # backend
        location ~ ^/(api|pictrs|feeds|nodeinfo|.well-known) {
            proxy_pass "http://lemmy";
            # proxy common stuff
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";

            # Send actual client IP upstream
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
}

EOF

      }
    }
  }
  group "frontend" {
    network {
      mode = "bridge"
      port "http" { to = 80 }
    }

    task "lemmy-ui" {
      driver = "docker"

      config {
        image = "dessalines/lemmy-ui:${var.lemmy_version}"
        ports = ["ui"]
      }
      env {
        # this needs to match the hostname defined in the lemmy service
        # set the outside hostname here
        LEMMY_UI_LEMMY_EXTERNAL_HOST = "${var.instance_name}"
        LEMMY_UI_HOST                = "0.0.0.0:${NOMAD_PORT_http}"
        # set up HTTPS!
        LEMMY_HTTPS    = false
        LEMMY_UI_DEBUG = true
      }

      service {
        name     = "lemmy-ui"
        provider = "nomad"
        port     = "http"
        check {
          name     = "alive"
          type     = "tcp"
          interval = "20s"
          timeout  = "2s"
          check_restart {
            limit           = 3
            grace           = "30s"
            ignore_warnings = false
          }
        }
      }
      template {
        destination = "config/.env"
        env         = true
        change_mode = "restart"
        data        = <<-EOF
{{ range $i, $s := nomadService "lemmy" }}
{{- if eq $i 0 -}}
LEMMY_UI_LEMMY_INTERNAL_HOST = {{ .Address }}:{{ .Port }}
{{- end -}}
{{ end }}
EOF
      }
      resources {
        cpu    = 90
        memory = 90
      }
    }
  }

  group "backend" {

    restart {
      interval = "10m"
      attempts = 8
      delay    = "15s"
      mode     = "delay"
    }
    network {
      mode = "bridge"
      port "lemmy" {}
      port "db" {}
    }

    task "lemmy" {
      driver = "docker"

      config {
        image = "dessalines/lemmy:${var.lemmy_version}"
        volumes = [
          "local/lemmy.hjson:/etc/lemmy/lemmy.hjson",
        ]
      }
      env {
        LEMMY_CONFIG_LOCATION = "/etc/lemmy/lemmy.hjson"
        RUST_LOG              = "warn"
      }

      service {
        name     = "lemmy"
        port     = "lemmy"
        provider = "nomad"
        check {
          name     = "alive"
          type     = "tcp"
          interval = "20s"
          timeout  = "2s"
          check_restart {
            limit           = 4
            grace           = "20s"
            ignore_warnings = false
          }
        }
      }
      template {

        change_mode = "restart"
        destination = "local/lemmy.hjson"
        data        = <<EOH
{
  database: {
    {{ with nomadVar "nomad/jobs/lemmy" }}
    password: "{{ .db_password }}"
    {{ end }}
    {{ range nomadService "lemmy-db" }}
    host: "{{ .Address }}"
    port: {{ .Port }}
    {{ end }}
    user: "lemmy"
    database: "lemmy"
    pool_size: 5
  }
  # replace with your domain
  hostname: ${var.instance_name}
  bind: "0.0.0.0"
  port: {{ env "NOMAD_PORT_lemmy" }}
  federation: {
    enabled: false
  }
  # 
  #pictrs: {
  #  url: "http://localhost:8080/"
  #}
  # Whether the site is available over TLS. Needs to be true for federation to work.
  #tls_enabled: true
  setup: {
    # Username for the admin user
    admin_username: "admin"
    # Password for the admin user. It must be at least 10 characters.
    admin_password: "YOUR_ADMIN_PASSWORD"
    # Name of the site (can be changed later)
    site_name: "YOUR SITE NAME HERE"
    # Email for the admin user (optional, can be omitted and set later through the website)
    # admin_email: "YOUR@EMAIL.HERE"
  }
}
EOH
      }
      resources {
        cpu = 100
        # docs say it should use about 150 MB
        memory = 200
      }
    }

  }
  group "postgres" {
    restart {
      attempts = 4
      interval = "30m"
      delay    = "20s"
      mode     = "fail"
    }
    volume "postgres" {
      type      = "host"
      read_only = false
      source    = "lemmy-data"
    }
    network {
      mode = "bridge"
      port "postgres" { to = 5432 }
    }
    task "postgres" {
      driver = "docker"
      config {
        image = "postgres:15.2"
        ports = ["postgres"]
      }
      env = {
        "POSTGRES_USER" = "lemmy"
        "POSTGRES_DB"   = "lemmy"
      }
      template {
        destination = "config/.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
{{- with nomadVar "nomad/jobs/lemmy" -}}
POSTGRES_PASSWORD={{ .db_password }}
{{- end -}}
EOH

      }
      volume_mount {
        volume      = "postgres"
        destination = "/var/lib/postgresql/data"
        read_only   = false
      }
      resources {
        cpu    = 120
        memory = 250
      }
      service {
        name     = "lemmy-db"
        port     = "postgres"
        provider = "nomad"
        check {
          name     = "alive"
          type     = "tcp"
          interval = "20s"
          timeout  = "2s"
        }
      }
    }
  }
}