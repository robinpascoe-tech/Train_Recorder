# Security

This repository is meant to be safe to publish without live feed credentials.

Do not commit:

- Broadcastify/Icecast passwords
- Broadcastify mountpoints
- live `site.yaml` files
- live `rtl_airband.conf` files
- rclone config files or cloud tokens
- generated recordings
- local `.env` or override files

`/etc/train-recorder/site.yaml` can contain Broadcastify/Icecast credentials. Treat it as a live local config, not a file to copy back into the repository.

If a credential is committed, rotate it with the provider first. Then remove it from git history before pushing the repository publicly.
