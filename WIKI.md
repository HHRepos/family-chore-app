# OMyDays — Project Wiki

> **Last updated:** 2026-05-07
> **Version:** iOS 1.0.1 (Build 4) — TestFlight
> **API:** https://4aeyo9z2hf.execute-api.eu-west-1.amazonaws.com/v1
> **Status:** Mobile-only (web validation code removed 2026-05-07)

---

## Table of Contents

- [Overview](#overview)
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
- **Extra chores** — Children can claim additional chores from other days for bonus points
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
| GET | `/v1/users/{id}/extra-chores` | Available extra chores |
| POST | `/v1/users/{id}/extra-chores` | Claim an extra chore |
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
- Extra chores: children claim bonus tasks for more points
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
