-- Allow `child_invitations.family_id` to be NULL for the kid-invites-parent
-- flow: an authenticated child without a family generates a 6-char code, the
-- parent enters it later, and only THEN does the family get created. Until
-- the parent claims, there's no family yet.
--
-- Live Lambda has been INSERTing NULL here since the kid-explore flow
-- shipped, but the original schema had NOT NULL → every "Invite Parent" tap
-- got a constraint violation.

ALTER TABLE child_invitations ALTER COLUMN family_id DROP NOT NULL;
