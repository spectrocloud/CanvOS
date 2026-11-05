# SUSE Linux Enterprise Micro

Kairos base on `registry.suse.com/suse/sle-micro/5.5`. The build registers
against SCC to pull the version-matched SLE 15 SP5 kernel and dracut, so it needs
a SUSE registration code. Any Docker host with BuildKit works; the host does not
need to run SLE Micro.

## Build

From `base-images/`, with the registration code in `SUSE_REGCODE`:

```bash
export SUSE_REGCODE='<registration code>'
docker buildx bake --allow=fs.read=.. slem-5-5 --load
```

The code reaches the build only as a BuildKit secret, never as a build arg or in
an image layer. Every build registers a fresh SCC system and deregisters it at the end
(`deregister` stage), so builds do not use up registrations; the registration
itself is bind-mounted into the steps that need it and never lands in a layer.
Because of that the steps after registration are rebuilt on every run (no layer
cache). A build that fails part-way leaves its system registered; remove it in SCC. The image is tagged
`<REGISTRY>/kairos-slem:5.5-core-<ARCH>-<MODEL>-<KAIROS_VERSION>`.
