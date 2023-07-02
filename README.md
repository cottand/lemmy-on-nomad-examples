# Lemmy Deployment on Nomad

Lemmy has well-documented Docker and Ansible deployment docs, from which you can derive a Nomad config. I thought I would share a variation of the one I am currently using as a starting point for whoever wants to selfhost Lemmy on Nomad rather than Docker or Ansible.

## Why

You may already have Nomad running and thus you would probably rather stay consistent and use the same orchestrator for all your services.

Some benefits of using Nomad (specifically for Lemmy) include:

- Horizontal scaling
    - You can run DB, frontend, backend, and pictrs in different machines.
    - You can set `count = X` for the backend, frontend and Nginx in order to scale traffic horizontally, also potentially across several machines
- Better health check support
- Rolling deployment options
    - you can set up Nomad to use rolling deployments for when you update your config or your container versions


## Requirements

They may not be the best choices for your specific set-up. But to keep it as simple, this job file:
- **Uses [Nomad Service Discovery](https://developer.hashicorp.com/nomad/docs/networking/service-discovery).** If you use Consul, you probably want to change this. The steps should be simple
    - Remove `provider = nomad` from services' declarations
    - Change `range nomadService` to `range service` in the themplates
- **Assumes you dealt with firewalls.** You probably won't want to expose the DB port to the outside world! The way I deal with this in my personal setup is to use [Multi-interface networking](https://www.hashicorp.com/blog/multi-interface-networking-and-cni-plugins-in-nomad-0-12) to expose private ports in a private network and public ports to the outside world
- **Assumes you have DNS/ingress set-up.** If your Nomad cluster has several clients, your Nginx instance could end up on any of these machines. You should make sure you use a [constraint](https://developer.hashicorp.com/nomad/docs/job-specification/constraint) to pin Nginx to a single box OR use some reverse proxy/load balancer to direct requests. I personally use [Traefik](https://doc.traefik.io/traefik/) (there are other options) but did not include that config here.
- **Uses a Nomad varialbe for the DB password.** This should be fine if no one else is an admin of your Nomad cluster, but otherwise you should replace this with whatever secret infra you use (Vault, hardocded...) or use Nomad ACLs to hide the variable.