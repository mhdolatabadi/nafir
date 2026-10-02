-- Accounts deleted by their owner. The users row and everything that cascades
-- from it go in the same statement that adds a row here, so the account can't
-- sign in again before its audio is removed. The audio under object_prefix is
-- removed right after, and again by a background job until purge_after, which
-- also catches uploads that were still in flight. purged_at records when the
-- prefix was last found empty after purge_after; the row is kept as an audit
-- trail and holds no personal data besides the old account ID.
CREATE TABLE IF NOT EXISTS account_deletions (
    user_id uuid PRIMARY KEY,
    object_prefix text NOT NULL CHECK (object_prefix LIKE 'users/%/'),
    deleted_at timestamptz NOT NULL DEFAULT now(),
    purge_after timestamptz NOT NULL,
    purged_at timestamptz
);

CREATE INDEX IF NOT EXISTS account_deletions_pending_idx
    ON account_deletions (deleted_at) WHERE purged_at IS NULL;
