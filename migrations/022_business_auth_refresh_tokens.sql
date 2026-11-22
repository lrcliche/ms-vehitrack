BEGIN;

CREATE TABLE IF NOT EXISTS business.auth_refresh_token (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES business."user"(id) ON DELETE CASCADE,
    tenant_user_id uuid NOT NULL REFERENCES business.tenant_user(id) ON DELETE CASCADE,
    tenant_id uuid NOT NULL REFERENCES public.tenant(id) ON DELETE CASCADE,
    token_hash text NOT NULL UNIQUE CHECK (length(token_hash) = 64),
    family_id uuid NOT NULL,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz,
    revoked_at timestamptz,
    CONSTRAINT auth_refresh_token_tenant_user_fk FOREIGN KEY (tenant_user_id, tenant_id)
        REFERENCES business.tenant_user(id, tenant_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS auth_refresh_token_family_idx
    ON business.auth_refresh_token(family_id);
CREATE INDEX IF NOT EXISTS auth_refresh_token_expiry_idx
    ON business.auth_refresh_token(expires_at) WHERE revoked_at IS NULL;

REVOKE ALL ON business.auth_refresh_token FROM PUBLIC;
GRANT SELECT, INSERT, UPDATE ON business.auth_refresh_token TO postgres;

COMMIT;
