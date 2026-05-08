-- 1) Avatar customizations storage. Each entry is a "key:value" pair the
--    iOS AvatarView appends to the DiceBear URL — e.g. "accessories:glasses-2",
--    "clothingColor:6dbdb1". Empty array = use the deterministic default.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS avatar_customizations TEXT[] NOT NULL DEFAULT '{}';

-- 2) Default new chores to auto-approve. The original Build 8 design only
--    auto-approved daily habits, which surprised testers expecting any chore
--    completion to award points immediately. New chores from this point land
--    auto-approved unless a parent flips it off.
ALTER TABLE chores ALTER COLUMN auto_approve SET DEFAULT TRUE;

-- 3) Backfill existing rows so today's chores match the new default.
UPDATE chores SET auto_approve = TRUE WHERE auto_approve = FALSE;
