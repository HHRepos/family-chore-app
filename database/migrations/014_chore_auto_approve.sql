-- Auto-approve flag on the chore master table.
--
-- Per-chore opt-in: when set, completing the chore moves it directly from
-- `pending` → `approved` and awards points, skipping the parent-review step.
-- Useful for daily habits (brush teeth, make bed) where parental oversight
-- on every tap is friction without value.

ALTER TABLE chores
  ADD COLUMN IF NOT EXISTS auto_approve BOOLEAN NOT NULL DEFAULT FALSE;

-- Daily habits default to auto-approve. Household / routine chores stay
-- behind the approval gate so parents can verify they were actually done.
UPDATE chores SET auto_approve = TRUE WHERE chore_type = 'daily_habit';
