-- Helpers

CREATE OR REPLACE FUNCTION app_org_id()
    RETURNS uuid AS
$$
BEGIN
    RETURN NULLIF(current_setting('app.org_id', true), '')::uuid;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION app_user_id()
    RETURNS uuid AS
$$
BEGIN
    RETURN NULLIF(current_setting('app.user_id', true), '')::uuid;
END;
$$ LANGUAGE plpgsql STABLE;
