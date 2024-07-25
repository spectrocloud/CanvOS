# Debugging Kairos

If you're facing hard-to-diagnose issues with your custom provider image, you can use the scripts in this directory to obtain verbose Kairos output.

## Steps
1. Use earthly to generate an ISO from your CanvOS provider image:
    ```
    earthly +build --PROVIDER_IMAGE=<your_provider_image>  # e.g., oci:tylergillson/ubuntu:k3s-1.26.4-v4.0.4-071c2c23
    ```
    If successful, `build/debug.iso` will be created.

2. Launch a local VM based on the debug ISO using QEMU and pipe all output to a log file:
    ```
    ./launch-qemu.sh build/debug.iso | tee out.log
    ```

3. Boot the VM in `Kairos (manual)` mode. Once booted, create `userdata.yaml` with your desired Kairos config and execute a manual Kairos installation: `kairos-agent --debug manual-install --device auto userdata.yaml`.

4. The VM should eventually reboot itself once the installation completes. Rather than waiting, execute `reboot` to return to the GRUB menu, select `Palette eXtended Kubernetes Edge` and hit `e` to edit it. Add `rd.debug rd.immucore.debug` to the end of the `linux` line, then hit `CTRL+x` to boot with your edits. You should see verbose Kairos debug logs and they will be persisted to `out.log`.
