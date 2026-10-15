-- Admins take a public playlist out of the popular list (#314) without
-- touching the playlist or its sharing. Every change is audited.
ALTER TABLE playlists ADD COLUMN IF NOT EXISTS popular_hidden_at timestamptz;
ALTER TABLE playlists ADD COLUMN IF NOT EXISTS popular_hidden_by uuid;

CREATE TABLE IF NOT EXISTS popular_playlist_audit (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    playlist_id uuid NOT NULL,
    actor_id uuid NOT NULL,
    hidden boolean NOT NULL,
    changed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS popular_playlist_audit_playlist ON popular_playlist_audit (playlist_id, changed_at DESC);

-- Admins delete a public playlist (#320); what was deleted, and by whom,
-- stays on record after the playlist is gone.
CREATE TABLE IF NOT EXISTS playlist_deletion_audit (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    playlist_id uuid NOT NULL,
    owner_id uuid NOT NULL,
    name text NOT NULL,
    actor_id uuid NOT NULL,
    deleted_at timestamptz NOT NULL DEFAULT now()
);
