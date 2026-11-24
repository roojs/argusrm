-- Agent-side win file identity (throwaway schema — not wired in product yet).
-- One row per PE path; invalidate when size or mtime changes.
-- Table ''win_file_identity'' in agent client_db (💩 path TBD).

CREATE TABLE IF NOT EXISTS win_file_identity (
	path                TEXT    NOT NULL PRIMARY KEY,
	size_bytes          INTEGER NOT NULL DEFAULT 0,
	mtime_unix          INTEGER NOT NULL DEFAULT 0,
	file_sha256         TEXT    NOT NULL DEFAULT '',
	signing_result      TEXT    NOT NULL DEFAULT '',
	signer_cert_sha256  TEXT    NOT NULL DEFAULT '',
	signer_subject_key_id TEXT  NOT NULL DEFAULT '',
	signer_publisher    TEXT    NOT NULL DEFAULT '',
	signer_issuer       TEXT    NOT NULL DEFAULT '',
	signer_serial       TEXT    NOT NULL DEFAULT '',
	scan_source         TEXT    NOT NULL DEFAULT '',
	scanned_dt          INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS win_file_identity_sha256 ON win_file_identity (file_sha256);
CREATE INDEX IF NOT EXISTS win_file_identity_signer ON win_file_identity (signer_cert_sha256);

-- scan_source: 'win32' | 'osquery' | 'win32+osquery' (throwaway may set both)
-- signer_publisher: human review (CN from cert; mirror osquery authenticode.subject_name when present)