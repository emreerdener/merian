-- A stable purchase-principal binding must not leave an empty Auth-UUID
-- customer on the legacy RevenueCat reconciliation worker. Subscriber GET is
-- get-or-create, so even a free queue row can manufacture an unwanted provider
-- shell after the installation has switched to its stable App User ID.
--
-- Preserve a real legacy lane during the compatibility window: a user with a
-- durable legacy entitlement snapshot may intentionally have both that input
-- and one or more stable principals. Only evidence-free queue rows are fenced.

SET lock_timeout = '5s';
SET statement_timeout = '30s';

CREATE OR REPLACE FUNCTION
internal.has_active_purchase_principal_relationship(
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
STRICT
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM internal.purchase_principal_bindings AS binding
        JOIN internal.purchase_principals AS principal
          ON principal.id = binding.purchase_principal_id
        WHERE binding.auth_user_id = p_user_id
          AND principal.status = 'active'
    ) OR EXISTS (
        SELECT 1
        FROM internal.purchase_principals AS principal
        WHERE principal.account_grant_owner_user_id = p_user_id
          AND principal.status = 'active'
    ) OR EXISTS (
        SELECT 1
        FROM internal.purchase_principals AS principal
        WHERE principal.revenuecat_app_user_id =
                internal.canonical_revenuecat_app_user_id(p_user_id)
          AND principal.status = 'active'
    )
$function$;

COMMENT ON FUNCTION
internal.has_active_purchase_principal_relationship(UUID) IS
    'Returns whether an Auth user is bound to, owns grants for, or owns the immutable provider ID of an active stable purchase principal.';

REVOKE ALL ON FUNCTION
    internal.has_active_purchase_principal_relationship(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION
internal.should_keep_legacy_revenuecat_reconciliation(
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
STRICT
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT
        NOT internal.has_active_purchase_principal_relationship(p_user_id)
        OR EXISTS (
            SELECT 1
            FROM internal.legacy_revenuecat_entitlement_state AS legacy
            WHERE legacy.merian_user_id = p_user_id
        )
$function$;

COMMENT ON FUNCTION
internal.should_keep_legacy_revenuecat_reconciliation(UUID) IS
    'Keeps legacy reconciliation for unconverted users and for stable-related users with durable legacy-provider state; rejects evidence-free UUID customer creation.';

REVOKE ALL ON FUNCTION
    internal.should_keep_legacy_revenuecat_reconciliation(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION
internal.guard_legacy_revenuecat_reconciliation_queue()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF NOT internal.should_keep_legacy_revenuecat_reconciliation(
        NEW.merian_user_id
    ) THEN
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION
internal.guard_legacy_revenuecat_reconciliation_queue() IS
    'Suppresses inserts and updates that would send an evidence-free stable-related Auth UUID to RevenueCat subscriber GET.';

REVOKE ALL ON FUNCTION
    internal.guard_legacy_revenuecat_reconciliation_queue()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS guard_legacy_revenuecat_reconciliation_queue
    ON internal.revenuecat_reconciliation_queue;
CREATE TRIGGER guard_legacy_revenuecat_reconciliation_queue
BEFORE INSERT OR UPDATE ON internal.revenuecat_reconciliation_queue
FOR EACH ROW
EXECUTE FUNCTION internal.guard_legacy_revenuecat_reconciliation_queue();

CREATE OR REPLACE FUNCTION
internal.fence_empty_legacy_revenuecat_queue_after_binding()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF TG_OP = 'INSERT'
       OR NEW.auth_user_id IS DISTINCT FROM OLD.auth_user_id THEN
        DELETE FROM internal.revenuecat_reconciliation_queue AS queue
        WHERE queue.merian_user_id = NEW.auth_user_id
          AND NOT EXISTS (
              SELECT 1
              FROM internal.legacy_revenuecat_entitlement_state AS legacy
              WHERE legacy.merian_user_id = NEW.auth_user_id
          );
    END IF;
    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION
internal.fence_empty_legacy_revenuecat_queue_after_binding() IS
    'Atomically removes an evidence-free legacy Auth-UUID queue when completion creates or moves a stable purchase-principal binding.';

REVOKE ALL ON FUNCTION
    internal.fence_empty_legacy_revenuecat_queue_after_binding()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS fence_empty_legacy_revenuecat_queue_after_binding
    ON internal.purchase_principal_bindings;
CREATE TRIGGER fence_empty_legacy_revenuecat_queue_after_binding
AFTER INSERT OR UPDATE OF auth_user_id
ON internal.purchase_principal_bindings
FOR EACH ROW
EXECUTE FUNCTION
    internal.fence_empty_legacy_revenuecat_queue_after_binding();

-- Repair rows created by the ordinary public.users enqueue trigger before this
-- fence existed. A row with a durable legacy snapshot is intentionally kept.
DELETE FROM internal.revenuecat_reconciliation_queue AS queue
USING (
    SELECT binding.auth_user_id AS user_id
    FROM internal.purchase_principal_bindings AS binding
    JOIN internal.purchase_principals AS principal
      ON principal.id = binding.purchase_principal_id
    WHERE principal.status = 'active'

    UNION

    SELECT principal.account_grant_owner_user_id AS user_id
    FROM internal.purchase_principals AS principal
    WHERE principal.status = 'active'
      AND principal.account_grant_owner_user_id IS NOT NULL

    UNION

    SELECT users.id AS user_id
    FROM public.users AS users
    JOIN internal.purchase_principals AS principal
      ON principal.revenuecat_app_user_id =
            internal.canonical_revenuecat_app_user_id(users.id)
    WHERE principal.status = 'active'
) AS active_relationship
WHERE queue.merian_user_id = active_relationship.user_id
  AND NOT EXISTS (
      SELECT 1
      FROM internal.legacy_revenuecat_entitlement_state AS legacy
      WHERE legacy.merian_user_id = queue.merian_user_id
  );

RESET statement_timeout;
RESET lock_timeout;
