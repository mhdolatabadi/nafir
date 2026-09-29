-- Messenger bots: which Nafir account a private chat is linked to, the
-- one-time codes that link them, processed updates, and audio imports.
CREATE TABLE IF NOT EXISTS bot_chats (
    provider text NOT NULL,
    chat_id text NOT NULL,
    user_id uuid REFERENCES users(id) ON DELETE CASCADE,
    linked_at timestamptz,
    -- Wrong link codes sent from this chat in the current window.
    failed_links integer NOT NULL DEFAULT 0,
    failed_since timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (provider, chat_id)
);

-- One-time codes a signed-in app user creates to link a bot chat to their
-- account. Only an HMAC of the code is stored.
CREATE TABLE IF NOT EXISTS bot_link_codes (
    code_hash bytea PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS bot_link_codes_user_idx ON bot_link_codes (user_id);

-- Providers redeliver webhooks; an update is handled at most once.
CREATE TABLE IF NOT EXISTS bot_updates (
    provider text NOT NULL,
    update_id text NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (provider, update_id)
);

CREATE TABLE IF NOT EXISTS bot_imports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider text NOT NULL,
    chat_id text NOT NULL,
    message_id text NOT NULL,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    file_id text NOT NULL,
    file_name text NOT NULL,
    title text,
    artist text,
    size_bytes bigint NOT NULL,
    state text NOT NULL DEFAULT 'queued'
        CHECK (state IN ('queued', 'downloading', 'done', 'failed')),
    track_id uuid REFERENCES tracks(id) ON DELETE SET NULL,
    error text,
    attempts integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (provider, chat_id, message_id)
);

CREATE INDEX IF NOT EXISTS bot_imports_unfinished_idx
    ON bot_imports (state, updated_at) WHERE state IN ('queued', 'downloading');
