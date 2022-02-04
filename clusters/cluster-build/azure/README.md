# How to use

Fill in these fields into the `values.yaml` file:

- clusterSet
- imageName (able to leave as default)
- region
- baseDomain
- resource_group
- network:
  - clusterCidr: xyz
  - machineCidr: 10.0.0.0/16 [leave as default]
  - serviceCidr: yyy

Create a new `create.sh` from `create.template.sh` and fill in the details.
Run `create.sh`. Copy `values.yaml` into an Application in the bootstrap repo. 