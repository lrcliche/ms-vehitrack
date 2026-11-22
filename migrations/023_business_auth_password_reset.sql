BEGIN;

CREATE TABLE IF NOT EXISTS business.auth_password_reset_token (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES business."user"(id) ON DELETE CASCADE,
    tenant_user_id uuid NOT NULL,
    tenant_id uuid NOT NULL REFERENCES public.tenant(id) ON DELETE CASCADE,
    token_hash text NOT NULL UNIQUE CHECK (length(token_hash) = 64),
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    consumed_at timestamptz,
    FOREIGN KEY (tenant_user_id, tenant_id)
        REFERENCES business.tenant_user(id, tenant_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS auth_password_reset_user_idx
    ON business.auth_password_reset_token(user_id, tenant_id)
    WHERE consumed_at IS NULL;
CREATE INDEX IF NOT EXISTS auth_password_reset_expiry_idx
    ON business.auth_password_reset_token(expires_at)
    WHERE consumed_at IS NULL;

REVOKE ALL ON business.auth_password_reset_token FROM PUBLIC;
GRANT SELECT, INSERT, UPDATE ON business.auth_password_reset_token TO postgres;
GRANT UPDATE (password_hash, updated_at) ON business."user" TO postgres;

COMMIT;
