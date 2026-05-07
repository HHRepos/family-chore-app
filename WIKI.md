# OMyDays — Project Wiki

> **Last updated:** 2026-05-07
> **Version:** iOS 1.0.1 (Build 6) — TestFlight
> **API:** https://4aeyo9z2hf.execute-api.eu-west-1.amazonaws.com/v1
> **Status:** Mobile-only (web validation code removed 2026-05-07)

---

## Table of Contents

- [Overview](#overview)
- [Product Manager](#product-manager)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Architecture](#architecture)
- [API Endpoints](#api-endpoints)
- [Database Schema](#database-schema)
- [Deployment](#deployment)
- [Roadmap](#roadmap)
- [Related Docs](#related-docs)
- [Changelog](#changelog)

---

## Overview

AI-powered family chore management app with voice-first onboarding, house scanning, gamified rewards, jobs board, and household routine management. Designed to reduce parental mental load by automating chore scheduling and making chores fun for kids through points, badges, and a rewards shop.

---

## Product Manager

> **Status snapshot — iOS 1.0.1 Build 6 (2026-05-07)**
> Mobile-only after the 2026-05-07 pivot. The legacy React web app was a validation prototype and has been removed. Build 6 removes the "bonus chores" pool and adds a fairness post-processor so every family member ends up with the same number of chores (within 1) and roughly the same points. Current focus: stabilize in TestFlight, then ship v1.1 (auth providers + push + inter-family leaderboard).

### Implementation Status

| Stage | What it means |
| --- | --- |
| ✅ Live | Implemented end-to-end (backend + iOS UI), shipped in Build 5 |
| ⚠️ Partial | One side missing (backend done, iOS pending — or vice versa) |
| ❌ Planned | On the roadmap, no code yet |

### Feature Matrix

#### Onboarding & Auth

| Feature | Status | Notes |
| --- | --- | --- |
| Email + password (registration + login) | ✅ | bcrypt, JWT 7-day expiry |
| Biometric login (Face ID / Touch ID) | ✅ | Crash-free in Build 5 (Face ID privacy string fix) |
| Family invite codes (6-char, no I/O/0/1) | ✅ | Shared flow for kids and partner parents |
| Voice-first onboarding | ✅ | Real GPT-4o calls, TTS via OpenAI `tts-1` (voice: nova) |
| House scanning (room photos → chores) | ✅ | GPT-4o Vision, smart appliance detection (robot vac, dishwasher) |
| Manual form fallback (5-step) | ✅ | Inline on the onboarding screen |
| Sign in with Apple | ❌ | Backend route missing; iOS framework imported, button hidden |
| Sign in with Google | ❌ | Backend route missing; needs GoogleSignIn pod |

#### Chore System

| Feature | Status | Notes |
| --- | --- | --- |
| AI 7-day distribution (GPT-4o-mini) | ✅ | Index-based IO, rule validation, deterministic fallback if AI sparse |
| Daily habit templates (brush teeth, bed, etc.) | ✅ | Auto-assigned to all eligible kids, age-gated |
| Pet & bin auto-chores | ✅ | Generated from `house_details` rotation config |
| Routine rotation (walks, litter, bins) | ✅ | Round-robin across configured children |
| Personal-space / shared-room chores | ✅ | `owner_user_ids[]` field, only owners get assigned |
| Transfer chore (100% points to recipient) | ✅ | `transfer_type='transfer'` |
| Support request (50 / 50 split) | ✅ | `transfer_type='support'`, both get `ceil(points/2)` |
| Fairness post-processor | ✅ | Build 6: rebalances chore counts/points across kids before insert |
| Approval workflow (pending → approved/rejected) | ✅ | Parent must approve before points award |
| Photo proof (optional `proof_image_url`) | ✅ | Field exists; iOS picker wiring partial |
| Star burst animation on completion | ✅ | iOS visual feedback |

#### Gamification & Rewards

| Feature | Status | Notes |
| --- | --- | --- |
| Points + difficulty tiers (10/15/25) | ✅ | Easy / Medium / Hard |
| XP + 15 levels (Apprentice → Mythic) | ✅ | 100 XP per level |
| Weekly badges (6-tier progression) | ✅ | Getting Started → Chore Champion |
| Streak tracking (5 fire tiers) | ✅ | Warm Up → Legendary, resets on miss |
| Weekly Superstar (silver) / Monthly Hero (gold) | ✅ | All chores every day for 7 / 30 days |
| Rewards shop (points → reward) | ✅ | Per-child targeting, auto-deduct on purchase |
| Curated default rewards (20) | ✅ | Seeded for new families during onboarding |
| In-family leaderboard | ✅ | Points-ranked, all roles can view |
| **Inter-family leaderboard** | ❌ | v1.1 priority. Needs opt-in privacy + family scoring endpoint |
| Avatar customisation | ❌ | Concept stage |
| Power-ups, seasonal events | ❌ | Future |

#### Jobs Board (Contracts)

| Feature | Status | Notes |
| --- | --- | --- |
| Open jobs (any kid claims) | ✅ | Status: open → assigned |
| Application jobs (parent picks winner) | ✅ | Reason + optional proposed price |
| Counter-offers (kid → parent) | ✅ | Parent accepts/rejects counter |
| Child-pitched jobs (entrepreneurship) | ✅ | Kid proposes → parent approves |
| Subcontracting (assigned kid → sibling) | ✅ | Pays from original reward |
| Cash rewards | ✅ | Parent confirms handover (no automation) |
| Credibility / overdue penalty | ⚠️ | Concept exists in WIKI; lambda wiring not verified end-to-end |

#### Family Management

| Feature | Status | Notes |
| --- | --- | --- |
| Add / edit / remove children | ✅ | Inline forms in Parent Settings |
| Add partner parent (via family code) | ✅ | Shared 6-char code |
| Edit member name / age / role | ✅ | `PATCH /v1/users/{id}` |
| Edit family name + house type | ✅ | `PATCH /v1/families` |
| Delete entire family (cascade) | ✅ | `DELETE /v1/families/{id}` |
| Parent participation (opt into chores) | ✅ | Settings toggle |
| Multi-household / co-parenting | ❌ | v2.0 — shared kids across two homes, custody-aware schedules |

#### House Rules & Screen Time

| Feature | Status | Notes |
| --- | --- | --- |
| Bin schedule (days, frequency, rotation) | ✅ | Stored in `house_details.bin_schedule` |
| Pet care config (walks, litter, feeding) | ✅ | Per-pet rotation arrays |
| Gaming schedule (per-child, per-device) | ✅ | Days, hours, device type |
| Screen time chore-gate (app level) | ✅ | Must complete chores + hit point threshold |
| **Deep iOS Screen Time API integration** | ❌ | Currently app-level only — no system-wide blocking |

#### Notifications

| Feature | Status | Notes |
| --- | --- | --- |
| Push notifications (APNs) | ❌ | No device token storage, no notifications table, no APNs cert |
| Email digests for parents | ❌ | v1.2 backlog |

### Chore System Deep Dive

#### Chore Types (`chore_type` field, migration 011)

| Type | Used for | Auto-assign | Min age (typical) |
| --- | --- | --- | --- |
| `daily_habit` | Hygiene & routine (brush teeth, make bed, shower) | All eligible kids, every day | 3+ |
| `household` | Standard chores (dishes, hoover, mop) | AI distribution, 7-day rotation | varies (4+/8+) |
| `routine` | Pets & bins | Rotation from `house_details` | 6+ |
| `personal_space` | Clean own room | Owner-specific only | 4+ |
| `laundry` | Per-child laundry | Rotation | 6+ |

#### Distribution Algorithm (the AI brain)

1. Fetch household members (children, plus parents if opted in).
2. Seed default chores for new families if the chore list is empty.
3. Auto-create pet + bin chores from `house_details` if missing.
4. Insert daily habits for the next 7 days (age-gated, all eligible kids).
5. Insert routine rotation assignments (pet walks, litter, bins).
6. Clear `pending` future household-chore assignments to avoid duplicates.
7. Call **GPT-4o-mini** with member + chore index lists → 7-day schedule.
8. Validate AI output: no duplicate chore on same day, age limits, valid indices.
9. If AI output too sparse, fall back to deterministic round-robin with offset.
10. Bulk-insert into `assigned_chores` with `status='pending'`.

#### Distribution Rules

- **No duplicate chore per day** across the family.
- **No consecutive-day repeats** for the same child.
- **Age tiers:** easy = any, medium = 4+, hard = 8+.
- **Daily habits** have their own `min_age` (often 3+).
- **Pet walks / litter** have higher minimums (6 – 8) for safety.

#### Point Math

| Action | Original child | Helper / recipient |
| --- | --- | --- |
| Approved | full points | n/a |
| Rejected | 0 | n/a |
| **Transferred** | 0 | 100% on approval |
| **Supported** (50/50) | `ceil(points/2)` | `ceil(points/2)` |

#### Status Flow

```
pending → in_progress → completed → approved   (full points awarded)
                                  → rejected   (no points)
```

Transfers and support requests sit on top of this flow — they don't change the status, only who gets credit when the parent approves.

### Key Product Decisions

| Date | Decision | Why |
| --- | --- | --- |
| 2026-04-02 | Validate concept via React web prototype | Test the idea before learning native iOS dev |
| 2026-04-14 | Build 4 distributed via TestFlight | First feature-complete iOS build |
| 2026-05-07 | **Pivot: mobile-only**, remove web validation | iOS reached parity; web was dead code |
| 2026-05-07 | Build 5 to fix Face ID crash | Missing `NSFaceIDUsageDescription` privacy string |
| 2026-05-07 | Adopt fastlane for TestFlight automation | Replace manual Xcode archive + upload |

### Next Up (v1.1 priorities)

Ranked by `user_value × delivery_cost`:

1. **Sign in with Apple** — App Store guideline 4.8 compliance + zero-friction returning users. Backend route + iOS button.
2. **Push notifications (APNs)** — chore reminders, approval alerts, badge unlocks. Needs APNs cert, device-token table, lambda hook on assignment/approval/badge events.
3. **Inter-family leaderboard** — opt-in family-vs-family scoring. Privacy decision needed (anonymous handle vs real family name).
4. **Sign in with Google** — broaden adoption beyond Apple ecosystem.
5. **Deep iOS Screen Time integration** — replace app-level chore gate with system-wide enforcement using Screen Time API.

### Open Questions

- **Inter-family leaderboard privacy:** opt-in only, anonymised handle, or display family name? Default-off?
- **Push frequency cap:** how many per kid per day before they tune out? (Gut: 3.)
- **Screen time philosophy:** pure block, or also reward extra time when kids over-deliver on chores?
- **Pricing:** free forever, freemium (premium = AI distribution / inter-family leaderboard), or flat family subscription?
- **Credibility system:** how harsh should overdue-job penalties be? (Currently designed as 20%.)

---

## Features

### Onboarding
- **Voice-first setup** — ChatGPT-style conversational UI with speech recognition and TTS
- **House scanning** — Upload room photos, GPT-4o Vision detects rooms/appliances and suggests chores
- **Smart appliance detection** — Recognizes robot vacuums, dishwashers, dryers; suggests maintenance tasks instead of manual equivalents
- **Rewards selection** — Parents pick from suggested rewards during setup
- **Manual form fallback** — 5-step form mode if voice isn't preferred

### Chore Management
- **AI-powered distribution** — GPT-4o-mini creates a fair 7-day schedule with rules:
  - No same chore for two children on the same day
  - No consecutive-day repeats for the same child
  - Age-appropriate filtering (Rookie: any age, Pro: 4+, Legend: 8+)
  - Fair rotation across all family members
- **Auto-generated chores** — Pet care and bin collection chores created automatically from family config
- **Chore frequency** — Daily or Weekly when adding chores
- **Fairness post-processing** — After AI distribution, the backend rebalances so every family member ends up within 1 chore of every other (and points stay roughly even). No bonus pool, no extras to claim — every chore is owned by someone the moment it's distributed.
- **Transfer system** — Children can transfer a chore to a sibling (100% points go to them)
- **Support system** — Children can ask a sibling for help (points split 50/50)
- **Parent participation** — Parents can opt-in to the chore rotation via Settings toggle
- **Star burst animation** — Visual feedback when completing a chore

### Gamification
- **Points system** — Earn points for completing chores, jobs, and bonus tasks
- **Difficulty tiers** — Rookie (easy/10pts), Pro (medium/15pts), Legend (hard/25pts)
- **Weekly badges** — Getting Started, On a Roll, Hard Worker, Super Helper, You're Cooking!, Chore Champion
- **Streak tracking** — Consecutive days with all chores done (Warm Up, On Fire, Blazing, Inferno, Legendary)
- **Weekly Superstar badge** (silver) — Complete all chores every day for the week
- **Monthly Hero badge** (gold) — Complete all chores every day for the month
- **Family leaderboard** — Ranked by points with medal indicators

### Rewards Shop
- **Points-based store** — Children browse and buy rewards with earned points
- **Galaxy-themed UI** — Twinkling star animations, glowing point balance
- **Per-child rewards** — Parents can assign specific rewards to specific children
- **Parent management view** — Add, edit, delete rewards directly from Shop tab
- **Purchase animation** — Green "Purchased!" feedback on buy

### Jobs Board
- **Parent posts jobs** — Title, description, reward (points or cash), due date
- **Two job types:**
  - **Open** — First come, first served (any child can claim instantly)
  - **Application** — Children submit applications with reason + optional bid; parent picks winner
- **Cash rewards** — Parent confirms cash handover after job completion
- **Credibility system** — Overdue assigned jobs auto-expire with 20% point penalty
- **Job lifecycle:** Open -> Assigned -> Completed -> Confirmed (or Expired)

### Family Rules
- **Bin collection schedule** — Collection days + weekly rotation between children
- **Pet care** — Dog walk rotation, cat litter rotation with age-appropriate filtering
- **Gaming schedule** — Per-child rules: device (PC/VR/Console/Tablet), allowed days, hours per session
- **Today's summary** — Shows whose turn for bins, pet care, and gaming allowances today
- **Visible to everyone** — Both parents and children see the Rules tab

### Room Scanning (Post-Setup)
- **Scan additional rooms** from Settings at any time
- **Appends** new rooms without overwriting existing data
- **Auto-creates chores** from AI suggestions

### Screen Time Management
- **Daily limits** — Set minutes per day per child
- **Chore-gated access** — Must complete daily chores to unlock screen time
- **Minimum points required** — Set point threshold for access

### User Management
- **Parent/child accounts** — Role-based views and permissions
- **Child invitations** — Generate invite links (7-day expiry) for children to create their own login
- **Family structure** — Multiple children, optional parent participation

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Mobile | SwiftUI / Swift 5+ — iOS 14+, distributed via TestFlight |
| Backend | Node.js 18 + TypeScript on AWS Lambda (consolidated, single function) |
| Database | PostgreSQL 14+ on AWS RDS |
| AI | OpenAI GPT-4 Turbo (conversation), GPT-4o (vision), GPT-4o-mini (scheduling) |
| Auth | Email/password (bcrypt), JWT, biometric (FaceID/TouchID), 6-char invite codes |
| Hosting | API Gateway + Lambda (eu-west-1) |
| Build | esbuild (Lambda), Xcode (iOS) |

---

## Architecture

```
family-chore-app/
+-- ios-app/             # SwiftUI iOS app (OMyDay), 52+ Swift files
|   +-- MyDay.xcodeproj  # Xcode project
|   +-- WIKI.md          # iOS-specific wiki (architecture, screens, models)
|   +-- wiki.html        # Rendered iOS wiki
+-- lambda-backend/      # Consolidated AWS Lambda (all API routes)
|   +-- src/index.ts     # Monolithic handler (~2.5k lines)
+-- database/
|   +-- migrations/      # 12 SQL migration files (Postgres on RDS)
+-- docs/                # Architecture, AWS infra, AI integration, DB schema
+-- WIKI.md              # This file (project-wide wiki)
+-- wiki.html            # Rendered project wiki
+-- serve_wiki.py        # Local wiki server: python3 serve_wiki.py -> :8765
+-- ROADMAP.md           # Feature backlog
+-- PM.md                # Product notes
```

**Production architecture:** SwiftUI iOS app talks to a single AWS Lambda function (behind API Gateway, eu-west-1) that handles all routes. Lambda persists to RDS Postgres. AI features call OpenAI directly from Lambda.

> Web validation code (React/Vite frontend + Express microservice packages + Lerna monorepo) was removed on 2026-05-07. The iOS app has full feature parity and is the only shipping client.

---

## API Endpoints

### Auth
| Method | Path | Description |
|--------|------|-------------|
| POST | `/v1/auth/register` | Create parent account |
| POST | `/v1/auth/login` | Login (returns JWT) |
| GET | `/v1/auth/profile` | Get current user profile |

### Families
| Method | Path | Description |
|--------|------|-------------|
| POST | `/v1/families` | Create family |
| GET | `/v1/families/{id}` | Get family details + house_details |
| PATCH | `/v1/families/{id}/config` | Update bins/pets/gaming config |
| POST | `/v1/families/{id}/members` | Add child to family |
| GET | `/v1/families/{id}/chores` | All assigned chores (parent view) |
| GET | `/v1/families/{id}/approvals` | Pending approvals |
| GET | `/v1/families/{id}/badges` | Weekly/monthly badges for all children |
| GET | `/v1/families/{id}/rewards` | Active rewards list |
| GET | `/v1/families/{id}/leaderboard` | Points leaderboard |
| GET | `/v1/families/{id}/jobs` | All jobs (auto-expires overdue) |
| POST | `/v1/families/{id}/rooms` | Store scanned rooms + create chores |

### Chores
| Method | Path | Description |
|--------|------|-------------|
| POST | `/v1/chores` | Create a chore |
| GET | `/v1/users/{id}/chores` | User's assigned chores |
| GET | `/v1/users/{id}/stats` | Total completed, streak, points |
| PATCH | `/v1/chores/assigned/{id}` | Update chore status |
| POST | `/v1/chores/assigned/{id}/approve` | Approve (handles split points) |
| POST | `/v1/chores/assigned/{id}/transfer` | Transfer chore to another user |
| POST | `/v1/chores/assigned/{id}/support` | Request help (50/50 split) |

### Rewards
| Method | Path | Description |
|--------|------|-------------|
| POST | `/v1/rewards` | Create reward |
| POST | `/v1/rewards/bulk` | Bulk create rewards |
| PATCH | `/v1/rewards/{id}` | Update reward |
| DELETE | `/v1/rewards/{id}` | Deactivate reward |
| POST | `/v1/rewards/redeem` | Redeem reward with points |

### Jobs
| Method | Path | Description |
|--------|------|-------------|
| POST | `/v1/jobs` | Create job (parent) |
| POST | `/v1/jobs/{id}/apply` | Apply/accept job (child) |
| GET | `/v1/jobs/{id}/applications` | View applications (parent) |
| POST | `/v1/jobs/{id}/assign` | Pick applicant (parent) |
| POST | `/v1/jobs/{id}/complete` | Mark job done (child) |
| POST | `/v1/jobs/{id}/confirm` | Confirm + award (parent) |

### AI
| Method | Path | Description |
|--------|------|-------------|
| POST | `/v1/ai/voice-setup` | Conversational onboarding |
| POST | `/v1/ai/tts` | Text-to-speech |
| POST | `/v1/ai/families/{id}/distribute-chores` | AI chore scheduling |
| POST | `/v1/ai/analyze-room` | GPT-4o Vision room analysis |

### Other
| Method | Path | Description |
|--------|------|-------------|
| POST | `/v1/children/{id}/invite` | Generate invite link |
| GET | `/v1/invitations/{token}` | Validate invitation |
| POST | `/v1/invitations/{token}/claim` | Claim invitation |
| GET/PUT | `/v1/users/{id}/screen-time` | Screen time settings |
| GET | `/v1/users/{id}/screen-time/access` | Check screen time access |
| GET/PATCH | `/v1/users/{id}/participate` | Parent chore participation |

---

## Database Schema

### Tables
| Table | Purpose |
|-------|---------|
| `families` | Family info + `house_details` JSONB (rooms, bins, pets, gaming) |
| `users` | Parent/child accounts, points, participation flag |
| `family_members` | Junction table (family <-> user) |
| `chores` | Master chore list per family (name, frequency, difficulty, points) |
| `assigned_chores` | Daily assignments (status, transfer tracking, unique constraint) |
| `rewards` | Reward catalog (per-family, optional per-child) |
| `user_rewards` | Redemption history |
| `screen_time_settings` | Per-child screen time rules |
| `points_history` | Point transaction log |
| `jobs` | Jobs board postings |
| `job_applications` | Job applications with reasons/bids |
| `child_invitations` | Invite tokens for child account creation |

### Key Columns
- `families.house_details` (JSONB) — stores `scanned_rooms`, `bin_schedule`, `pets`, `gaming_schedule`
- `assigned_chores.transferred_from` — tracks who transferred a chore
- `assigned_chores.transfer_type` — 'transfer' (full points) or 'support' (50/50 split)
- `users.participate_in_chores` — parent opt-in for chore rotation
- `rewards.child_id` — optional per-child reward assignment

### Migrations
1. `001_initial_schema.sql` — Core tables
2. `002_seed_data.sql` — Default chores and rewards
3. `003_child_invitations.sql` — Invite system
4. `004_reward_type.sql` — Reward type column
5. `005_reward_child_id.sql` — Per-child rewards
6. `006_jobs_board.sql` — Jobs + applications tables
7. `007_parent_participate.sql` — Parent participation flag
8. `008_unique_assigned_chores.sql` — Prevent duplicate assignments
9. `009_chore_transfers.sql` — Transfer/support tracking

---

## Deployment

### Infrastructure (AWS eu-west-1)
| Component | Resource |
|-----------|----------|
| API | API Gateway: `4aeyo9z2hf` |
| Backend | Lambda: `family-chore-api` (Node 18, 512MB, 60s timeout) |
| Database | RDS PostgreSQL: `family-chore-db.cxegq20iy20d.eu-west-1.rds.amazonaws.com` |
| iOS distribution | App Store Connect / TestFlight (bundle id `com.snow.omyday`) |

### Deploy Commands
```bash
# Backend (AWS Lambda)
cd lambda-backend && npm run build && npm run package
aws lambda update-function-code --function-name family-chore-api --zip-file fileb://function.zip --region eu-west-1 --profile claude-admin

# Database migration (run from lambda-backend with pg installed)
cd lambda-backend && node -e "const {Pool}=require('pg'); ..."

# iOS — Archive in Xcode, upload via App Store Connect / Transporter
```

---

## Roadmap

See [ROADMAP.md](ROADMAP.md) for the full feature backlog. Highlights:

### Coming in v1.1
- **Inter-Family Leaderboard** — Families compete globally. Family score = sum of all members' points. Opt-in privacy. Weekly & all-time rankings. "Top 10 Family" badge. Incentivizes collective effort.
- **iOS App Feature Parity** — Complete the MyDay game-style iOS app with all web features
- **Push Notifications** — Chore assignments, approvals, streak reminders, badge achievements

### Backlog (v1.2+)
- Notification system (push + in-app)
- Avatar customization (unlock outfits with points)
- Advanced gamification (daily login bonus, power-ups, seasonal events)
- Financial literacy (pocket money tracking, savings goals, gift cards)
- Deep screen time integration (iOS Screen Time API, gaming platform hooks)
- Social features (friend families, challenges, community)
- Analytics dashboard (weekly reports, trends, per-child insights)
- Multi-household support (co-parenting)
- Offline/PWA support
- AI Chore Coach, AR room detection, wearable integration

---

## Related Docs

| Document | Location | Description |
|----------|----------|-------------|
| Feature Roadmap | [ROADMAP.md](ROADMAP.md) | Full backlog with priorities |
| iOS App Wiki | [ios-app/WIKI.md](ios-app/WIKI.md) | Architecture, auth, screens, models, theme — iOS-specific |
| AI Integration | [docs/ai-integration-guide.md](docs/ai-integration-guide.md) | OpenAI usage patterns |
| AWS Infrastructure | [docs/aws-infrastructure-and-deployment.md](docs/aws-infrastructure-and-deployment.md) | Lambda, API Gateway, RDS setup |
| Database Schema | [docs/database-schema.md](docs/database-schema.md) | Full Postgres schema |
| Local Wiki Server | `python3 serve_wiki.py` → http://localhost:8765/ | Live-rendered hub for both wikis |

---

## Changelog

### 2026-05-07 (later) — Build 6

**End-to-end review pass.** Audited the data layer, the Lambda handlers, and the iOS persona flows; fixed every concrete bug found that wasn't a feature request. Highlights:

**Backend (data integrity):**
- **Migration 013** — added `'proposed'` and `'rejected'` to the `jobs.status` CHECK constraint. The Lambda has been inserting `'proposed'` for kid-pitched contracts since migration 010, but the original constraint from migration 006 didn't allow it. Live INSERTs were failing with a constraint violation.
- **Atomic reward redemption** — replaced the SELECT-check-UPDATE pattern with a single `UPDATE … WHERE points >= cost RETURNING points`. Two parallel redemption requests can no longer both pass the check and leave the user with negative points.
- **Atomic chore approval** — same compare-and-swap pattern: `UPDATE assigned_chores SET status='approved' WHERE id=$1 AND status<>'approved' RETURNING …`. Awards points only if the row was actually transitioned, so a double-approve race can't double-credit.
- **Date timezone fix** — date-only fields (`due_date`) were being wrapped in `new Date(…).toISOString().split('T')[0]`, which can shift by a day depending on the runtime TZ. Replaced with a UTC-explicit `dateOnly()` helper across the four read endpoints that returned dates.
- **Timestamp consistency** — `createdAt` and `completedAt` were being returned as raw pg objects from some endpoints. Wrapped in an `isoOrNull()` helper so iOS always sees ISO 8601 strings.
- **Family member response** — now includes `participates: bool` so the iOS app can tell which parents have opted into the chore rotation.

**iOS (persona flows):**
- **Parent participation visible in the child's transfer / support picker.** Previously `QuestDetailView.siblings` filtered for `role == 'child'`, so even if dad was in the rotation, kids couldn't transfer chores to him. The picker now uses `FamilyMember.inChoreRotation` (every child + any parent who participates).
- **Parent participation toggle now actually triggers redistribution.** Toggling the switch in Settings calls `setParticipation`, then re-runs `distributeChores` and reloads `choreStore` + `familyStore` so the parent shows up in (or disappears from) the rotation immediately. Guarded with a `participatesLoaded` flag so the initial `.task`-driven value emission no longer triggers a redistribute on every Settings open.
- **Parent home screen refreshes on foreground.** Added a `scenePhase` observer to `CommandCenterView` mirroring the one in `QuestMapView`, so points / approvals / chore counts stay live without a manual pull-to-refresh.
- **Fix: stale points on the child's home screen.** After a chore was approved, the points pill at the top of the Quest Map kept showing the pre-approval total. The backend awards points correctly on `users.points`, but the iOS `ShopStore.points` cache was never invalidated. Fixed by:
  - Refreshing `ShopStore.loadAll()` when the app returns to the foreground (`scenePhase == .active`)
  - Refreshing when the child closes the chore detail sheet, leaderboard sheet, or all-chores sheet (anywhere they could have transitioned to/from chore approval)
  - Refreshing the parent's `ShopStore` after an approve/reject so leaderboard + their own totals stay in sync
  - Reloading family chores after approve/reject so the parent's chores tab updates immediately
- **Removed bonus / extra chores feature.** The "Bonus" button on the Quest Map and the `GET/POST /v1/users/{id}/extra-chores` endpoints have been deleted. Every chore is now owned by a specific child the moment it's distributed — there is no pool of unclaimed chores for kids to grab for bonus points. The point rationale: bonus chores favoured the most motivated child and undermined the fairness goal.
- **Added fairness post-processor.** After the AI (or fallback) builds the 7-day schedule, the backend now runs a balancing pass that moves chores from the busiest child to the least-loaded one until counts are within 1 of each other (subject to age constraints). Total points per child are tracked alongside and reported in CloudWatch logs. Without this, the AI could drift to "everyone gets 2/day" locally while leaving global totals uneven once age filters dropped assignments.
- **Tightened AI distribution prompt.** Replaced the soft "Rotate fairly across the week" line with explicit rules: same total chores per person (within 1), points within ~10%, and a mix of difficulties so no one is stuck with all-hard or all-easy.
- **iOS deletions:** `ExtraQuestsView.swift`, the `ExtraChore` model, `ChoreStore.extraChores`, `APIClient.getExtraChores` / `claimExtraChore`, the "Bonus" pill and its sheet on `QuestMapView`.
- **Bumped `CURRENT_PROJECT_VERSION` 5 → 6.** `MARKETING_VERSION` stays at 1.0.1.

### 2026-05-07 (later) — Build 5
- **Fix: Face ID login crash.** App was hard-terminated by iOS the first time the user tapped "Sign in with Face ID" on the Welcome Back screen. Root cause: `NSFaceIDUsageDescription` was missing from the Xcode-generated Info.plist (other privacy strings were present — Camera, Microphone, Speech — but not Face ID). Added `INFOPLIST_KEY_NSFaceIDUsageDescription` to both Debug and Release build configurations. No code changes — Keychain biometric flow in [`KeychainHelper.loadCredentialsWithBiometric`](ios-app/MyDay/Services/KeychainHelper.swift) was already correct.
- **Bumped `CURRENT_PROJECT_VERSION` 4 → 5** so the fix can be uploaded as a new TestFlight build. `MARKETING_VERSION` stays at 1.0.1 (same logical version, fix-only).

### 2026-05-07
- **Pivot to mobile-only.** The web app was a validation prototype; the iOS app now has full feature parity and is the only shipping client.
- Removed `packages/web-app/` (React/Vite frontend), the four legacy microservice packages (`user-service`, `chore-service`, `gamification-service`, `ai-service`), Lerna config, root `package.json` / `package-lock.json`, and `node_modules/`. All API logic lives in `lambda-backend/src/index.ts`.
- Removed web-only docs: `docs/api-specifications.md`, `docs/project-structure-and-config.md`, `docs/quick-start-guide.md`.
- Bumped iOS `MARKETING_VERSION` to 1.0.1 in the Xcode project (matches Build 4 on TestFlight).
- Added `serve_wiki.py` — local wiki hub at http://localhost:8765/ that live-renders both this wiki and the iOS-specific wiki.
- Renamed wiki title to **OMyDays** to match the app branding; updated `Tech Stack`, `Architecture`, `Deployment`, and `Related Docs` sections to reflect mobile-only scope.

### 2026-04-14
- **OMyDay iOS app v1.0.1 (Build 4) on TestFlight**
- 52 Swift files, full feature parity with web app + new features
- Smart auth (email, invite codes, biometric, kid exploring)
- AI onboarding with GPT-4o (voice + text, bins, pets, room scanning)
- Chore system v2: morning/evening routines, daily habits, household chores, pet rotation
- Contracts board (renamed from Bounties): kid pitching, portfolio, subcontracting
- Guided room scanning: name room → upload 1-4 photos → AI merges assets
- Unified invite codes (6-char): children, partners, link exploring kids
- Manage Family Members: add, invite, edit, remove, change role
- Manage Home: edit family name + house type
- Delete Family: cascading delete with confirmation
- Business Portfolio: reliability score, earnings, business levels
- Play Time & Gaming rules with device icons and weekend badges
- All backend endpoints deployed to AWS Lambda

### 2026-04-05
- MyDay iOS app created (35 Swift files — SwiftUI game-style RPG chore app)
- Feature roadmap & backlog created (ROADMAP.md)
- Game concept wiki created (MyDay/GAME-WIKI.md)
- Inter-family leaderboard concept designed (v1.1)

### 2026-04-02
- Auto-generate pet care and bin chores during distribution
- Chore transfer system (full transfer to sibling, all points go to them)
- Support system (ask sibling for help, 50/50 point split)
- Project wiki created

### 2026-03-30
- Fixed AI chore distribution: index-based AI communication, unique DB constraint, clear old assignments before redistributing
- Lowered age thresholds: Pro from 4+, Legend from 8+

### 2026-03-29
- Room scanning in Settings (post-setup)
- Chore frequency dropdown (Daily/Weekly) in Add Chore form
- Bin collection schedule with weekly child rotation
- Pet care management (dog walks, cat litter, rotation)
- Gaming schedule per child (device, days, hours)
- Family Rules page visible to all family members
- Fixed dashboard 0/0 count (date format normalization)
- Gaming difficulty renamed: Easy->Rookie, Medium->Pro, Hard->Legend
- Smart chore distribution (no same-day duplicates, no consecutive repeats)
- Enhanced room AI: detects smart appliances, suggests maintenance tasks
- Invite card hidden when all children registered
- Parent participation toggle for chore rotation
- Shop tab for parents (reward management)
- Fixed Shop keyboard dismissal bug on Safari
- Removed reward categories (all rewards available anytime)
- AI-powered chore distribution with GPT-4o-mini
- Interactive dashboard (clickable stats navigate to relevant pages)

### 2026-03-29 (earlier)
- Jobs Board: post jobs, applications, bidding, cash rewards, credibility system
- Rewards Shop with galaxy theme and purchase animations
- Rewards page with stats, weekly badges, streak tracking
- Star burst animation on chore completion
- Per-child reward customization
- Weekly Superstar (silver) and Monthly Hero (gold) badges
- Reward management in Settings (add/edit/delete with categories)
- Fixed dashboard for parents (family-wide chore view)
- Fixed Chores tab for parents (shows all children's chores)
- Safari landscape nav fix
- Fixed onboarding redirect loop (family restored from API on refresh)
- Rewards selection during onboarding setup
- Voice-first onboarding with room scanning
- Initial deployment to AWS
