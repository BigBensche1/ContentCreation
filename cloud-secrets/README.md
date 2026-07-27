# cloud-secrets/

Committed on purpose, despite containing real credentials — the `/schedule` cloud
scheduled-agent feature has no environment-level secrets mechanism, and this repo is
private, so this is the pragmatic trade-off for now.

This is **separate** from the project's local `.env` / `service-account.json` (which stay
gitignored). If credentials rotate, update both places.

At the start of each scheduled run, the agent copies:
- `cloud-secrets/gcp-service-account.json` → `./service-account.json`
- `cloud-secrets/schedule.env` → `./.env`

If this repo is ever made public, rotate every credential in here first (new Google
service-account key, new Resend API key) and remove this folder from git history.
