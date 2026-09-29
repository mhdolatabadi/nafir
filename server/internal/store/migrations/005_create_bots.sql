-- Messenger bots: which Nafir account a private chat is signed in to, the
-- email one-time codes used to sign in, processed updates, and audio imports.
CREATE TABLE IF NOT EXISTS bot_chats (
    provider text NOT NULL,
    chat_id text NOT NULL,
    state text NOT NULL DEFAULT 'idle'
        CHECK (state IN ('idle', 'awaiting_email', 'awaiting_code')),
    user_id uuid REFERENCES users(id) ON DELETE CASCADE,
    signed_in_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (provider, chat_id)
);

-- user_id is null when the email has no account: the chat is told the same
-- thing either way, and such a code can never be verified.
CREATE TABLE IF NOT EXISTS bot_login_codes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider text NOT NULL,
    chat_id text NOT NULL,
    email text NOT NULL,
    user_id uuid REFERENCES users(id) ON DELETE CASCADE,
    code_hash bytea NOT NULL,
    attempts integer NOT NULL DEFAULT 0,
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS bot_login_codes_chat_idx
    ON bot_login_codes (provider, chat_id, created_at DESC);
CREATE INDEX IF NOT EXISTS bot_login_codes_email_idx
    ON bot_login_codes (email, created_at DESC);

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
