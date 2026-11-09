# pstore persistence (PE-9067)

Nothing here is distribution-specific. Copied to `/usr` by the pstore block in the `Earthfile`, today on every Ubuntu
24.04 amd64 non-UKI image, with or without kdump (FIPS, STIG and CIS images included).

* `usr/lib/systemd/pstore.conf.d/persist.conf` — `systemd-pstore` moves pstore records into the journal (`Storage=journal`)
  instead of `/var/lib/systemd/pstore`, which is in memory on Kairos and lost at the next reboot. It is under `/usr/lib`,
  not `/etc`: `/etc/systemd` is a persistent bind mount on Kairos that keeps the first copy of a file, so a later image
  could not change or remove it.

Read the records with `journalctl -t systemd-pstore`. Independent of kdump: with kdump armed, a panic goes to the capture
kernel and pstore records nothing; pstore covers hosts where kdump is off or not loaded, the recovery system, and panics
before kdump arms.
