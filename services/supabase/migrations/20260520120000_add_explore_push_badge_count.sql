DROP FUNCTION IF EXISTS public.get_explore_push_notification_payload(UUID);

CREATE OR REPLACE FUNCTION public.get_explore_push_notification_payload(target_notification_id UUID)
RETURNS TABLE(
    notification_id UUID,
    recipient_user_id UUID,
    post_id UUID,
    type public.explore_notification_type,
    action_count INTEGER,
    reaction_emoji TEXT,
    comment_body TEXT,
    triggering_user_name TEXT,
    recent_actor_names TEXT[],
    is_reply_to_viewer_comment BOOLEAN,
    unread_count INTEGER
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        n.notification_id,
        epn.user_id AS recipient_user_id,
        n.post_id,
        n.type,
        n.action_count,
        n.reaction_emoji,
        n.comment_body,
        n.triggering_user_name,
        n.recent_actor_names,
        n.is_reply_to_viewer_comment,
        public.get_unread_explore_notification_count(epn.user_id) AS unread_count
    FROM public.explore_post_notifications epn
    JOIN LATERAL public.get_explore_notifications(epn.user_id, 1000000, NULL, NULL) n
        ON n.notification_id = epn.id
    WHERE epn.id = target_notification_id
      AND n.type <> 'follow';
$$;
