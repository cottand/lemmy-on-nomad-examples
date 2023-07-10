# Nomad Service discovery with Traefik ingress

This uses Traefik as a proxy/ingress.

## Requirements

They may not be the best choices for your specific set-up. But to keep it as simple, this job file:
- **Uses [Nomad Service Discovery](https://developer.hashicorp.com/nomad/docs/networking/service-discovery).** If you use Consul, you probably want to change this. The steps should be simple
    - Remove `provider = nomad` from services' declarations
    - Change `range nomadService` to `range service` in the themplates
- **Assumes a client with a volume `lemmy-data`.** You need to create a volume with this name in one of your Nomad clients so there is somewhere to store the Postgres data. You probably will want to set up back ups for it too!
- **Assumes you dealt with firewalls.** You probably won't want to expose the DB port to the outside world! The way I deal with this in my personal setup is to use [Multi-interface networking](https://www.hashicorp.com/blog/multi-interface-networking-and-cni-plugins-in-nomad-0-12) to expose private ports in a private network and public ports to the outside world
- **Assumes you have DNS and a traefik job set-up.** Traefik with Nomad service discovery should already be running in
your Nomad cluster for the tags set in this job to work. In Traefik, this config assumes
  - you dealt with TLS certificates in order to provide secure HTTPS traffic and your Traefik TLS `certresolver` is called `lets-encrypt` (you should change this if it is not the case).
  - you have a `websecure` entrypoint for public HTTPS traffic on port 443.
- **Uses a Nomad varialbe for the DB password.** This should be fine if no one else is an admin of your Nomad cluster, but otherwise you should replace this with whatever secret infra you use (Vault, hardocded...) or use Nomad ACLs to hide the variable.