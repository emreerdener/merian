-- The actors primary key and recent-activity index both lead with
-- activity_group_id. Add the reverse lookup required to enforce the user FK
-- without scanning the table during account deletion or identity maintenance.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

CREATE INDEX idx_community_identification_activity_actors_user_id
    ON internal.community_identification_activity_actors(user_id);

RESET lock_timeout;
RESET statement_timeout;
