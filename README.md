# WIP

Requirements X86 Hardware with 4cpu and 8GB Memory

## Basic Use Case
1. Fork or clone repo.  If cloning recommend Staring for change updates.
2. Add commands to [Dockerfile](./Dockerfile)
3. Add customizations and rename [user-data.yaml.tmp](./user-data.yaml.tmp) to user-data.yaml
4. Add customizations and rename [.variables.env.tmp](./variables.env.tmp) to variables.env
5. Run `build.sh`

`ex. 3pings/core-ubuntu-lts-22-k3s:demo-v1.24.6-k3s1_v3.3.3`

IMAGE_REPOSITORY | Prefix | OS_FLAVOR | K8S_FLAVOR | CANVOS_ENV | k8s_version | K8S_FLAVOR_TAG | SPECTRO_VERSION
| :---------: | :---------: | :---------: | :---------: | :---------: | :---------: | :---------: | :---------: |
| ttl.sh | core | ubuntu-lts-22 | k3s | demo | 1.24.6 | k3s1 | 3.3.3 |


### Folder Layout
