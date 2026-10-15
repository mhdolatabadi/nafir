-- «گزارش تخلف» for store entries (#243): a signed-in listener reports an
-- entry; admins review the reports and may hide it. One open report per
-- reporter and entry. Reports go with the entry, and with the reporter's
-- account.
CREATE TABLE IF NOT EXISTS store_reports (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entry_id uuid NOT NULL REFERENCES store_entries(id) ON DELETE CASCADE,
    reporter_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason text NOT NULL,
    details text,
    created_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    resolved_by uuid
);

CREATE UNIQUE INDEX IF NOT EXISTS store_reports_open_idx
    ON store_reports (entry_id, reporter_id) WHERE resolved_at IS NULL;
CREATE INDEX IF NOT EXISTS store_reports_pending_idx
    ON store_reports (created_at) WHERE resolved_at IS NULL;
