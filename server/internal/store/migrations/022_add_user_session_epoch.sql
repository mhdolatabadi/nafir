-- Every access token carries the epoch it was issued in; moving it on ends
-- all of the account's sessions at once (#216).
ALTER TABLE users ADD COLUMN session_epoch bigint NOT NULL DEFAULT 0;
