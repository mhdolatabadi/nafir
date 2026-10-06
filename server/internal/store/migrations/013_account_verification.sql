ALTER TABLE users ADD COLUMN verified boolean NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN verified_at timestamptz;
ALTER TABLE users ADD COLUMN verified_by uuid;

CREATE TABLE account_verification_audit (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id uuid NOT NULL,
    actor_id uuid NOT NULL,
    verified boolean NOT NULL,
    changed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX account_verification_audit_account ON account_verification_audit (account_id, changed_at DESC);
