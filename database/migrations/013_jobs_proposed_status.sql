-- Allow `'proposed'` as a valid jobs.status. The Lambda backend has been
-- inserting this value for child-pitched contracts since migration 010
-- (proposed_price column), but the original CHECK constraint from
-- migration 006 only listed: open / assigned / completed / confirmed /
-- expired. Live INSERTs would fail with a constraint violation.

ALTER TABLE jobs DROP CONSTRAINT IF EXISTS jobs_status_check;

ALTER TABLE jobs
  ADD CONSTRAINT jobs_status_check
  CHECK (status IN ('open', 'proposed', 'assigned', 'completed', 'confirmed', 'expired', 'rejected'));

-- We also add `'rejected'` so parents can decline a kid-pitched contract
-- without deleting the row (preserves history for the Business Portfolio).
