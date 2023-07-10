variable "lemmy_version" {
  type    = string
  default = "0.18.1"
}
variable "instance_name" {
  type    = string
  default = "your.url.here.com"
}

job "lemmy" {
  datacenters = ["dc1"]
  type        = "service"

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
        LEMMY_UI_LEMMY_EXTERNAL_HOST = "${var.instance_name}"
        LEMMY_UI_HOST                = "0.0.0.0:${NOMAD_PORT_http}"
        # make sure traefik deals with HTTPS!
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
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_TASK_NAME}.rule=Host(`${var.instance_name}`)",
          "traefik.http.routers.${NOMAD_TASK_NAME}.entrypoints=websecure",
          "traefik.http.routers.${NOMAD_TASK_NAME}.tls=true",
          "traefik.http.routers.${NOMAD_TASK_NAME}.tls.certresolver=lets-encrypt",
        ]
      }
      template {
        destination = "config/.env"
        env         = true
        change_mode = "restart"
        data        = <<-EOF
{{ range $i, $s := nomadService "lemmy-be" }}
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
        name     = "lemmy-be"
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
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_TASK_NAME}.rule=Host(`${var.instance_name}`) && (PathPrefix(`/api`) || PathPrefix(`/pictrs`) || PathPrefix(`/feeds`) || PathPrefix(`/nodeinfo`) || PathPrefix(`/.well-known`) || Method(`POST`) || HeaderRegexp(`Accept`, `^[Aa]pplication/.*`))",
          "traefik.http.routers.${NOMAD_TASK_NAME}.entrypoints=websecure",
          "traefik.http.routers.${NOMAD_TASK_NAME}.tls=true",
          "traefik.http.routers.${NOMAD_TASK_NAME}.tls.certresolver=lets-encrypt",
        ]
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