-- Email verification (#206), separate from the admin's manual verification
-- badge in users.verified. Accounts that existed before this migration are
-- treated as verified so nobody is locked out.
ALTER TABLE users ADD COLUMN email_verified_at timestamptz;
UPDATE users SET email_verified_at = created_at;

-- The one outstanding code per account. Only a keyed hash of the code is
-- stored; it is bound to the address it was sent to, so changing the email
-- invalidates it.
CREATE TABLE email_verification_codes (
    user_id uuid PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    email text NOT NULL,
    code_hash text NOT NULL,
    expires_at timestamptz NOT NULL,
    attempts integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now()
);
