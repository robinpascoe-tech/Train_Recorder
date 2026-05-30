# Security

This repository is meant to be safe to publish without live feed credentials.

Do not commit:

- Broadcastify/Icecast passwords
- Broadcastify mountpoints
- rclone config files or cloud tokens
- generated recordings
- local `.env` or override files

If a credential is committed, rotate it with the provider first. Then remove it from git history before pushing the repository publicly.
