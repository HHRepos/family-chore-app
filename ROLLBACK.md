# Rollback to Build 14 (pre–Living Garden redesign)

The state of OMyDays as of **2026-05-10** has been preserved as a recoverable
checkpoint. If the Living Garden redesign turns out to be a wrong turn (in
testing, or in user feedback, or for any other reason), this document has
the exact steps to get back to Build 14.

## What was preserved

| Asset | Where | How to access |
| --- | --- | --- |
| **iOS source code** | Git tag `v1.0.1-build14` + branch `legacy/build14-pre-redesign` | `git checkout v1.0.1-build14` |
| **iOS binary** | TestFlight (App Store Connect → Apps → OMyDay → TestFlight → Builds → 14) | Direct from App Store Connect UI; no rebuild needed |
| **Backend source** | Same git tag — `lambda-backend/src/index.ts` at that commit | `git checkout v1.0.1-build14 -- lambda-backend/` |
| **Backend bundle** | Rebuildable from source via `npm run build:server` | Same as above |
| **Database schema** | All 16 migrations are committed in `database/migrations/` | Replay any subset against a fresh DB |
| **Database data** | Live Postgres on Lightsail VM + Lightsail auto-snapshots (free, 7-day retention) | Lightsail console or AWS CLI |
| **Old AWS Lambda** | Still exists at `family-chore-api` (eu-west-1) but no longer receives traffic | `aws lambda invoke` or re-point API Gateway |

## Rollback paths, ranked by simplicity

### Path A — iOS-only rollback (fastest, ~5 min)

Use this if the redesign ships and testers prefer Build 14. The backend
stays as is; only TestFlight gets pointed at the older binary.

1. App Store Connect → Apps → OMyDay → TestFlight → Builds
2. Open Build 14, click **Distribute → Add to Group**
3. Add the testing group(s) you want on Build 14
4. Optionally remove newer builds from the group so testers stop seeing them

That's it. TestFlight pushes Build 14 to all members of the group. Build 14
points at `https://54-171-244-65.nip.io/v1` — same backend as today — so
nothing on the server side changes.

### Path B — Backend rollback (used only if a backend change broke something)

The Lightsail VM and DB are unchanged across builds. But if a future
backend deploy breaks something, here's the rebuild:

```bash
# In a clean working directory
git clone https://github.com/HHRepos/family-chore-app.git
cd family-chore-app
git checkout v1.0.1-build14

# Build the legacy server bundle
cd lambda-backend
npm install
npm run build:server

# Deploy to Lightsail (uses the existing key)
cd ..
scp -i .lightsail/key.pem -o StrictHostKeyChecking=no \
    lambda-backend/dist/server.js \
    ubuntu@54.171.244.65:/tmp/server.js
ssh -i .lightsail/key.pem -o StrictHostKeyChecking=no ubuntu@54.171.244.65 \
    'sudo cp /tmp/server.js /opt/omyday/current/server.js && \
     sudo chown omyday:omyday /opt/omyday/current/server.js && \
     sudo systemctl restart omyday'
```

Total time: ~3 min.

### Path C — Database restore from snapshot

Used only if data corruption occurs. Lightsail keeps automatic daily
snapshots. To restore:

```bash
# List recent snapshots
aws lightsail get-instance-snapshots \
    --profile claude-direct --region eu-west-1 \
    --query 'instanceSnapshots[?fromInstanceName==`omyday-api`]' \
    --output table

# Create a new instance from a chosen snapshot (does not delete current)
aws lightsail create-instances-from-snapshot \
    --instance-names omyday-api-restore \
    --availability-zone eu-west-1a \
    --instance-snapshot-name <snapshot-name> \
    --bundle-id micro_3_0 \
    --profile claude-direct --region eu-west-1
```

Then either swap the static IP to the new instance, or copy data out and
import to the live one. **Do this only with explicit need — restoring
overwrites current state.**

### Path D — Full nuclear: rebuild everything from scratch

If the Lightsail VM is somehow lost (user error, region outage, IAM
mistake), the full rebuild is documented inline in WIKI.md under
`## Deployment`. The 16 migrations + the source code at the tag are
sufficient to bring the entire backend back from zero.

## What's NOT preserved (and why it doesn't matter)

| Thing | Why it's fine |
| --- | --- |
| **Old Lambda + RDS infrastructure** | Was decommissioned during the Build 7 migration. The data was migrated to Lightsail. No rollback to "the way it was before Lightsail" — that ship has sailed. |
| **TestFlight feedback** | Lives in App Store Connect; persists across builds. |
| **Avatar customizations + chore data** | Lives in Postgres; persists across iOS builds. |

## How to verify the backup is complete

```bash
# Tag exists and is correct
cd /Users/ayataly/Claude\ Projects/family-chore-app
git show v1.0.1-build14 --stat | head

# Branch exists and points at the right commit
git log legacy/build14-pre-redesign --oneline | head -3

# Both are pushed to origin
git ls-remote --tags origin | grep v1.0.1-build14
git ls-remote --heads origin | grep legacy/build14-pre-redesign
```

All four should produce output. If any are silent, the backup isn't
complete and rollback can't be guaranteed.

---

Document author: 2026-05-10 · Living Garden redesign begins on `main`
from the next commit.
