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

## Available examples

So far, we have examples of Lemmy set up using:
- [Nomad service discovery + Nginx Proxy](nomad-discovery-nginx/README.md)
- [Nomad service discovery + Traefik Proxy]((nomad-discovery-traefik/README.md))