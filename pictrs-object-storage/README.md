# Pict-rs with object storage

This uses some S3-compatible storage to store pictrs media, as well as the obligatory sled file databse in a volume.

## Requirements
They may not be the best choices for your specific set-up. But to keep it as simple, this job file:
- **Uses [Nomad Service Discovery](https://developer.hashicorp.com/nomad/docs/networking/service-discovery).** If you use Consul, you probably want to change this. The steps should be simple
    - Remove `provider = nomad` from services' declarations
    - Change `range nomadService` to `range service` in the themplates
- **You must set up the volume for sled in the job file.** Look for `TODO set up volume`
- **You must provide credentials for the bucket**.
  - You can fill the job file directly - look for `TODO add bucket credentials`
  - You can provide Nomad variables that contain the necessary data. This is the recommended approach because the API keys should be secret and probably not uploaded directly in the job file (you can use Vault instead but you will have to change the job file accordingly).