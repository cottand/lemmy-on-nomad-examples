# Nomad Service discovery with Nginx proxy

This uses Nginx as a proxy, based on the official recommended configuration which can be found [here](https://raw.githubusercontent.com/LemmyNet/lemmy-ansible/main/templates/nginx.conf) (without SSL).

## Requirements

They may not be the best choices for your specific set-up. But to keep it as simple, this job file:
- **Uses [Nomad Service Discovery](https://developer.hashicorp.com/nomad/docs/networking/service-discovery).** If you use Consul, you probably want to change this. The steps should be simple
    - Remove `provider = nomad` from services' declarations
    - Change `range nomadService` to `range service` in the themplates
- **Assumes a client with a volume `lemmy-data`.** You need to create a volume with this name in one of your Nomad clients so there is somewhere to store the Postgres data. You probably will want to set up back ups for it too!
- **Assumes you dealt with firewalls.** You probably won't want to expose the DB port to the outside world! The way I deal with this in my personal setup is to use [Multi-interface networking](https://www.hashicorp.com/blog/multi-interface-networking-and-cni-plugins-in-nomad-0-12) to expose private ports in a private network and public ports to the outside world
- **Assumes you have DNS/ingress set-up.** If your Nomad cluster has several clients, your Nginx instance could end up on any of these machines. You should make sure you use a [constraint](https://developer.hashicorp.com/nomad/docs/job-specification/constraint) to pin Nginx to a single box OR use some reverse proxy/load balancer to direct requests. You will also need to
deal with SSL for federation to work.
- **Uses a Nomad varialbe for the DB password.** This should be fine if no one else is an admin of your Nomad cluster, but otherwise you should replace this with whatever secret infra you use (Vault, hardocded...) or use Nomad ACLs to hide the variable.