# MyDay iOS App — Wiki

> **Last updated:** 2026-05-09
> **Version:** 1.0.1 (Build 14) — TestFlight
> **Platform:** iOS 14+ (SwiftUI 5)
> **Bundle ID:** com.snow.omyday
> **API:** https://54-171-244-65.nip.io/v1

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Auth Flow](#auth-flow)
- [App Routing](#app-routing)
- [Child Experience](#child-experience)
- [Parent Experience](#parent-experience)
- [Shared Views](#shared-views)
- [Onboarding](#onboarding)
- [API Endpoints](#api-endpoints)
- [Models](#models)
- [Theme & Design](#theme--design)
- [Roadmap](#roadmap)
- [Changelog](#changelog)

---

## Overview

MyDay is a gamified family chore management iOS app. Children complete "quests" (chores) to earn XP and points, which they spend in a rewards shop. Parents manage chores, approve completions, post bounties (jobs), and configure household routines. The app uses a dark game theme with neon accents.

**52 Swift files** — SwiftUI, Observation framework, no third-party dependencies.

---

## Architecture

```
ios-app/
├── MyDay.xcodeproj
└── MyDay/
    ├── MyDayApp.swift              # Entry point + routing
    ├── ContentView.swift           # Xcode compatibility
    ├── Models/                     # Data models (8 files)
    │   ├── User.swift
    │   ├── Chore.swift
    │   ├── Family.swift
    │   ├── Job.swift
    │   ├── Reward.swift
    │   ├── GameModels.swift
    │   ├── ScreenTime.swift
    │   └── CuratedRewards.swift
    ├── Services/                   # API + Keychain (2 files)
    │   ├── APIClient.swift
    │   └── KeychainHelper.swift
    ├── Stores/                     # State management (4 files)
    │   ├── AuthManager.swift
    │   ├── ChoreStore.swift
    │   ├── FamilyStore.swift
    │   └── ShopStore.swift
    ├── Theme/                      # Colors + styles (2 files)
    │   ├── GameColors.swift
    │   └── GameTheme.swift
    └── Views/
        ├── Auth/                   # Smart auth (3 files)
        │   ├── SmartAuthView.swift
        │   ├── FamilyCodeAuthView.swift
        │   └── WelcomeBackView.swift
        ├── Onboarding/             # Family setup (2 files)
        │   ├── OnboardingView.swift (SetupFamilyFlow)
        │   └── AIChatOnboardingView.swift
        ├── Child/                  # Child-only views (4 files)
        │   ├── QuestMapView.swift
        │   ├── QuestDetailView.swift
        │   ├── ExtraQuestsView.swift
        │   └── ProfileView.swift
        ├── Parent/                 # Parent-only views (5 files)
        │   ├── CommandCenterView.swift
        │   ├── ApprovalsView.swift
        │   ├── ParentSettingsView.swift
        │   ├── ParentShopView.swift
        │   └── RoomScanView.swift
        ├── Shared/                 # Both roles (6 files)
        │   ├── BountyBoardView.swift
        │   ├── ShopView.swift
        │   ├── LeaderboardView.swift
        │   ├── FamilyRulesView.swift
        │   ├── ScreenTimeView.swift
        │   └── AllChoresView.swift
        ├── Components/             # Reusable UI (8 files)
        │   ├── GameTabBar.swift
        │   ├── QuestCard.swift
        │   ├── XPBar.swift
        │   ├── StreakMeter.swift
        │   ├── StreakBadges.swift
        │   ├── WeeklyBadges.swift
        │   ├── BadgeGrid.swift
        │   └── ParticleEffect.swift
        └── MainTabView.swift
```

---

## Auth Flow

### Smart Auth — One Screen, Multiple Paths

The app uses a single `SmartAuthView` that replaces traditional role selection + separate login/register screens.

| Path | Taps | Who |
|------|------|-----|
| **Sign in with Apple** | 1-2 | Anyone |
| **Sign in with Google** | 1-2 | Anyone (pending SDK) |
| **Email login** | 3 | Returning users |
| **Email register** | 5 | New users (tap "New here?") |
| **Family code join** | 4 | Children / Parent 2 |
| **Kid exploring** | 4 | Child without code |
| **Biometric (Face ID)** | 1 | Returning users |

### How It Works

1. **No role selection** — the API profile response contains the role
2. **Login + Register on same screen** — "New here?" expands the name field inline
3. **"I have a family code"** — prominent link for children joining
4. **"I'm a kid exploring"** — kids register standalone, join family later
5. **Biometric** — saved credentials in Keychain with Face ID protection

### Routing Logic (MyDayApp.swift)

```
Loading → LaunchView
Not auth + has biometric creds → WelcomeBackView (Face ID)
Not auth → SmartAuthView
Auth + parent + no family → SetupFamilyFlow (inline onboarding)
Auth + child + no family → MainTabView (with join prompt)
Auth + has family → MainTabView
```

---

## App Routing

### Child Tabs

| Tab | View | Features |
|-----|------|----------|
| Quests | QuestMapView | Today's chores, XP bar, streak, quick actions, tips |
| Shop | ShopView | Browse & buy rewards with points |
| Bounties | BountyBoardView | Accept/apply for jobs |
| Rules | FamilyRulesView | View household rules, today's duties |
| Profile | ProfileView | Stats, badges, streak badges, logout |

### Parent Tabs

| Tab | View | Features |
|-----|------|----------|
| HQ | CommandCenterView | Family overview, stats, invite card, badges, redistribute |
| Approve | ApprovalsView | Approve/reject completed chores |
| Bounties | BountyBoardView | Create/confirm jobs, review applications |
| Shop | ParentShopView | Add/edit/delete rewards, per-child targeting |
| Settings | ParentSettingsView | Family config, chores, routines, room scan, participation |

---

## Child Experience

### QuestMapView (Daily Hub)
- Welcome greeting + points balance
- XP bar with level + title (Apprentice → Mythic)
- Streak counter (if active)
- Quick actions: Bonus Quests, Rankings, Screen Time
- Today's missions with active/completed split
- "See All" link → AllChoresView (multi-day, filtered)
- Tips section (when daily chores are done)
- Star burst animation on quest completion

### QuestDetailView
- Accept Mission → Start chore
- Mission Complete → Submit for approval
- Transfer → Give chore to sibling (100% XP to them)
- Ask Help → Split with sibling (50/50 XP)
- Status display: Awaiting Approval, Approved

### ProfileView
- Avatar (first letter), level, title
- Stats: All Time, This Week, Points
- Streak meter (7-day visual with flames)
- Weekly badges (6 tiers: Getting Started → Chore Champion)
- Streak badges (5 tiers: Warm Up → Legendary)
- Status badges (Weekly Superstar, Monthly Hero)
- Logout

### ShopView
- Point balance display
- 2-column reward grid
- Buy button (enabled if affordable)
- Purchase animation (green checkmark, 2s)

---

## Parent Experience

### CommandCenterView (HQ)
- Quick stats: Today's Quests, Pending Approvals, Family Members
- Quick actions: Rankings, Rules, Screen Time, View All Chores
- Invite card (if children without accounts exist)
- Children overview with progress per child
- Badges display
- Redistribute Quests button (AI-powered)

### ApprovalsView
- Pending chore cards with child name, points, difficulty, date
- Transfer/support indicators
- Approve (green) + Reject (gray) buttons
- Tips section

### ParentShopView
- Add reward form (name, description, cost, child targeting)
- Edit/delete existing rewards
- Per-child or all-children assignment

### ParentSettingsView
- Profile card with family code
- Add Child / Invite Child
- Manage Chores + Redistribute
- Manage Rewards
- Household Routines: Bin Collection, Pet Care, Gaming Schedule, Room Scanning
- Parent participation toggle
- Web dashboard link
- Logout

### Room Scanning (RoomScanView)
- Photo picker for room images
- AI analysis via GPT-4o Vision
- Detected rooms with confidence, assets, suggested chores
- Save rooms + auto-create chores

---

## Shared Views

### AllChoresView
- Multi-day chore list grouped by date (Today, Tomorrow, etc.)
- Filter tabs: All / Pending / Completed
- Parent sees child names on chore cards
- Child can tap chores for detail view

### BountyBoardView (Jobs Board)
- **Child**: Accept open jobs, apply with reason+bid, mark complete
- **Parent**: Create bounties (points/cash, open/application), confirm, review applications
- Role-guarded actions and sheets

### FamilyRulesView
- **Child**: "Today's Duties" summary (your turn highlights), own gaming schedule only
- **Parent**: Full view of all rooms, bins, pets, gaming for all children

### ScreenTimeView
- **Child**: Access status (locked/unlocked), requirements, daily limit
- **Parent**: Per-child configuration (daily limit, chore gate, min points)

### LeaderboardView
- Family rankings by points with medal display

---

## Onboarding

### SetupFamilyFlow (for new parents)

Integrated into registration — not a separate screen.

**Options:**
1. **Join existing family** — for parent 2 (enter code, skip all setup)
2. **Chat with AI** — conversational setup with GPT-4 Turbo + speech recognition + TTS
3. **Manual setup** — step-by-step form

**Manual Steps:**
1. Family name + house type
2. Add children (name + age)
3. Select rewards (20 curated: daily/weekly/family targets)

**AI Chat Features:**
- Speech recognition (iOS Speech framework)
- Text-to-speech (API + fallback to AVSpeechSynthesizer)
- Typing indicator (bouncing dots)
- Real-time extracted data card
- Auto-transition to rewards when complete

---

## API Endpoints

All endpoints use Bearer JWT authentication. Base URL: `https://4aeyo9z2hf.execute-api.eu-west-1.amazonaws.com/v1`

### Auth
| Method | Path | Description |
|--------|------|-------------|
| POST | `/auth/login` | Email+password login |
| POST | `/auth/register` | Create account |
| GET | `/auth/profile` | Get current user |

### Family
| Method | Path | Description |
|--------|------|-------------|
| POST | `/families` | Create family |
| GET | `/families/{id}` | Get family + members |
| POST | `/families/join` | Join via code |
| POST | `/families/{id}/members` | Add child |
| PATCH | `/families/{id}/config` | Update routines |
| POST | `/families/{id}/rooms` | Save scanned rooms |

### Chores
| Method | Path | Description |
|--------|------|-------------|
| POST | `/chores` | Create chore |
| GET | `/users/{id}/chores` | User's chores |
| GET | `/families/{id}/chores` | Family chores |
| PATCH | `/chores/assigned/{id}` | Update status |
| POST | `/chores/assigned/{id}/approve` | Approve |
| POST | `/chores/assigned/{id}/transfer` | Transfer |
| POST | `/chores/assigned/{id}/support` | Request help |

### Gamification
| Method | Path | Description |
|--------|------|-------------|
| GET | `/users/{id}/stats` | User statistics |
| GET | `/users/{id}/points` | Point balance |
| GET | `/families/{id}/badges` | Badge data |
| GET | `/families/{id}/leaderboard` | Rankings |
| GET | `/families/{id}/approvals` | Pending approvals |

### Rewards & Jobs
| Method | Path | Description |
|--------|------|-------------|
| GET | `/families/{id}/rewards` | Reward catalog |
| POST | `/rewards` | Create reward |
| POST | `/rewards/bulk` | Bulk create |
| PATCH | `/rewards/{id}` | Update |
| DELETE | `/rewards/{id}` | Delete |
| POST | `/rewards/redeem` | Redeem |
| GET | `/families/{id}/jobs` | Jobs list |
| POST | `/jobs` | Create job |
| POST | `/jobs/{id}/apply` | Apply/accept |
| POST | `/jobs/{id}/assign` | Pick winner |
| POST | `/jobs/{id}/complete` | Mark done |
| POST | `/jobs/{id}/confirm` | Confirm + award |

### Screen Time & AI
| Method | Path | Description |
|--------|------|-------------|
| GET | `/users/{id}/screen-time` | Settings |
| PUT | `/users/{id}/screen-time` | Update settings |
| GET | `/users/{id}/screen-time/access` | Check access |
| POST | `/ai/voice-setup` | Chat onboarding |
| POST | `/ai/tts` | Text-to-speech |
| POST | `/ai/families/{id}/distribute-chores` | AI distribute |
| POST | `/ai/analyze-room` | Room detection |

---

## Models

| Model | Key Fields |
|-------|-----------|
| User | userId, email, firstName, role, familyId, points, emoji |
| Family | familyId, familyName, familyCode, houseDetails, members |
| AssignedChore | assignedChoreId, choreName, status, points, difficulty, transferType |
| ExtraChore | choreId, choreName, difficulty, points |
| Reward | rewardId, rewardName, pointCost, childId, isActive |
| Job | jobId, title, rewardType, rewardAmount, jobType, status |
| Badge | userId, weeklySuperstar, monthlyHero |
| LeaderboardEntry | rank, name, points |
| UserStats | totalCompleted, weekCompleted, streak, totalPoints |
| ScreenTimeSettings | dailyLimitMinutes, requireDailyChores, minimumPoints |
| GameLevel | 100 XP/level, titles: Apprentice→Mythic |

---

## Theme & Design

- **Dark game background** (#0B0F1A) with neon accents
- **Colors**: neonBlue, neonGreen, neonPurple, neonOrange, neonYellow, neonRed, neonPink
- **Difficulty**: Quick ⚡ (green), Standard 🔧 (yellow), Challenge 💪 (red)
- **Components**: GameTextField, NeonButtonStyle, SecondaryButtonStyle, gameCard modifier, neonGlow modifier
- **Animations**: Star burst on completion, pulsing logo, spring tab transitions

---

## Roadmap

### Implementation Pipeline
- **Sign in with Apple** — Backend `POST /auth/apple` needed. iOS framework ready. HIGH priority.
- **Sign in with Google** — Backend `POST /auth/google` + GoogleSignIn SDK. HIGH priority.
- **Kid avatars / character customization** — Minecraft-style characters kids can customize with earned points (outfits, accessories, skins). Displayed on leaderboard, quest cards, profile.
- **Avatar builder during registration** — visual character creator instead of emoji picker

---

## Changelog

> The full changelog (with backend + infra context) lives in the [project wiki](../WIKI.md#changelog). Below is the iOS-side summary of Builds 7–14.

### 2026-05-09 — Build 14
- **Skills profile.** Six derived skills on `ProfileView` (Discipline, Responsibility, Initiative, Reliability, Teamwork, Entrepreneurship) — backed by `GET /v1/users/{id}/skills`. New `Skill` model + `SkillCard` component. Loaded alongside other shop data in `ShopStore.loadAll`.
- **Pet day-of-week schedule.** `Pet` model gains `walkDays` / `litterDays`. `PetConfigView` adds a 7-chip Mon–Sun selector.

### 2026-05-09 — Build 13
- **Kid-explore "Invite Parent" no longer errors.** Backend migration 016 dropped `child_invitations.family_id` NOT NULL. Backend `families/join` now accepts either `family_code` or `invite_code`.
- **ClaimInviteView** detects `auth.isAuthenticated` and skips email/password re-entry, calling `joinFamily` on the existing token.
- **Single consolidated invite-code input** with invisible TextField overlay + long-press Paste.
- **CommandCenterView** drops the decorative 2x2 grid icon, gains a "My chores today" section for participating parents.
- **PetConfigView** rotation picker now shows for every pet type.
- **FamilyRulesView → House Schedule.** Removed the duplicate "Today's Duties" section. Pet section gets a 7-day rotation strip matching the bin-collection visual.

### 2026-05-09 — Build 12
- **Avatar save bug fixed** (typed `AvatarUpdateResponse` so decode doesn't throw on the `user_id` String).
- **Avatar style switched to `pixel-art`** (Minecraft-feel) — open-peeps was "creepy" per testers. Customization sheet rebuilt around pixel-art's parameter set.
- **One-button completion** in `QuestDetailView` — the Accept → Complete two-step is gone.
- **Daily habits + pet routines hide Transfer / Ask Help.**
- **Cash uses regional currency** via `NumberFormatter` + `Locale.current`. New `RewardFormat` helper.
- **Pitch contract has an optional due date** (DatePicker, defaults to +7 days).
- **Pitch entry button** is an explicit "□+ Propose" capsule instead of the bare lightbulb icon.
- **Keyboard dismisses** after Add Reward / Add Chore via `@FocusState`.

### 2026-05-08 — Build 11
- **Auto-approve every chore** (was just daily habits in Build 8). Migration 015 flipped the default and backfilled rows. Tap "Mission Complete!" → points award immediately, `+N` pop animation fires.
- **Avatar customization sheet** at `Components/AvatarConfigView.swift`. Picker for hair, accessories, clothing colour, skin tone. Saves to new `users.avatar_customizations` array via `PATCH /v1/users/{id}/avatar`. All `AvatarView` call sites read from the user's stored customizations end-to-end.

### 2026-05-08 — Build 10
- **Full-body avatars** for every family member, generated by DiceBear's open-peeps style seeded from `userId`. New `Components/AvatarView.swift` with size variants. Wired into Profile, Quest Map header, Leaderboard rows, Parent Settings.
- **TestFlight encryption / France prompt** auto-answered via `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` — no more manual checkbox after upload.

### 2026-05-08 — Build 9
- **Pet rotation falls back to all kids** when the per-pet array is empty (live data was orphaning Fifi's litter). Existing `Feed Fifi` and `Clean Fifi's litter` re-tagged from `household` → `routine` so the rotation logic finds them.
- **Weekly "Refill {pet}'s feeder" chore** auto-generated alongside daily feed.
- **Family Rules kid view filtering** — Scanned Rooms hidden from kids; bin + pet sections filter by rotation membership.

### 2026-05-08 — Build 8
- **Stars now count immediately** when chore is approved. `ShopStore` polls every 10s on `QuestMapView` while foregrounded; refreshes on `scenePhase` changes and sheet dismissals. `+N` pop overlay on the points pill when `shop.points` jumps, with haptic.
- **Auto-approve flag on chores** (migration 014). Daily habits default to true; tapping complete on those skips the parent-review step.

### 2026-05-08 — Build 7 (infra migration)
- **Backend pointed at the new Lightsail VM** at `https://54-171-244-65.nip.io/v1` (was AWS Lambda + API Gateway + RDS, ~$25/mo → $7/mo). No code rewrite — the existing Lambda handler runs unchanged inside an Express wrapper.
- **`APIClient.baseURL`** updated to the nip.io endpoint.

### 2026-05-07 (later) — Build 6
- **Removed bonus / extra chores.** Deleted `ExtraQuestsView`, `ExtraChore` model, `ChoreStore.extraChores`, `APIClient.getExtraChores` / `claimExtraChore`, and the "Bonus" pill on `QuestMapView`. Backend endpoints `GET/POST /v1/users/{id}/extra-chores` were removed alongside.
- **Fairness post-processor on the backend.** AI-built schedules now get rebalanced so chore counts per family member are within 1 of each other (and points are roughly even).
- **Bumped `CURRENT_PROJECT_VERSION` 5 → 6.**

### 2026-05-07 — Build 5
- **Fix: Face ID login crash** — added `INFOPLIST_KEY_NSFaceIDUsageDescription` to Debug + Release configs.
- **Bumped `CURRENT_PROJECT_VERSION` 4 → 5.**

### 2026-04-14
- **TestFlight Build 4** (v1.0.1) published for beta testing
- **Fixed invite code input** — keyboard now appears, supports paste (was broken hidden TextField)
- **Fixed code input** in LinkChildView — same fix
- **Removed all flickering star animations** — clean static backgrounds
- **Simplified launch animation** — single spring entrance, no particles
- **Database wiped** for fresh testing

### 2026-04-13
- **App renamed to OMyDay** with custom app icon (dark theme, sparkle, gradient)
- **Published to TestFlight** (Build 1, 2, 3)
- **Manage Home** — edit family name and house type from Settings
- **Delete Family** — nuclear option with confirmation, removes all data
- **Room scanning redesigned** — name room first, upload 1-4 photos, merge assets
- **Image resize fix** — photos compressed to 1024px before analysis (was failing on 12MP iPhone photos)
- **Onboarding persistence** — progress saved to UserDefaults across app restarts
- **Removed Apple/Google Sign In buttons** (backend not ready, moved to pipeline)
- **Keyboard dismisses** on tap outside text fields
- **Difficulty renamed** — Quick ⚡ / Standard 🔧 / Challenge 💪
- **Extra chores filtered** — no habits/routine in bonus list
- **Pet chores from config** — walk, feed, litter auto-created with rotation
- **Duplicate chore fix** — redistribute no longer creates duplicates
- **Unified invite codes** — family code removed, partner invites via code
- **Manage Family Members** — add, invite, link, edit, remove, change role
- **Child-to-parent linking** — exploring kid generates code
- **Contracts board** — renamed from Bounties, kid pitching, portfolio
- **Chore system v2** — morning/evening routines, daily habits
- **App renamed to OMyDay** with custom app icon (dark theme, sparkle, gradient)
- **Removed Apple/Google Sign In buttons** (moved to pipeline — backend not ready)
- **Keyboard dismisses on tap** outside text fields
- **Published to TestFlight** for beta testing
- **All changes pushed to GitHub**

### 2026-04-12
- **Contracts board** — renamed from Bounties, kid pitching, business portfolio, subcontracting
- **Chore system v2** — morning/evening routines, daily habits, household chores, pet rotation
- **Unified invite codes** — 6-char codes for children + partners, removed family code
- **Manage Family Members** — add, invite, link, edit, remove, change role
- **Child-to-parent linking** — exploring kid generates code for parent
- **Difficulty renamed** — Quick ⚡ / Standard 🔧 / Challenge 💪
- **Extra chores filtered** — no more habits/routine tasks in bonus list
- **Pet chores from config** — walk, feed, litter auto-created with rotation
- **Duplicate fix** — redistribute no longer creates duplicate assignments
- **Animations** — launch particles, section slide-up, habit bounce, status dot pulse
- **Smart Auth Flow** — unified screen, biometric, invite codes, kid exploring
- **Integrated onboarding** — AI chat + manual, inline after registration

### 2026-04-09
- iOS app created with 50 Swift files
- Full feature parity with web app
- AI voice/text chat onboarding with Speech framework
- All chore management features (transfer, support, extra chores)
- Gamification (XP, levels, badges, streaks, leaderboard)
- Rewards shop (child buy, parent manage)
- Jobs board (open + application types)
- Family rules (bins, pets, gaming) with role filtering
- Screen time management (child status + parent config)
- Room scanning with GPT-4o Vision
- Multi-day chore view with filter tabs
- Streak badges (Warm Up → Legendary)
- Role-based view separation throughout
