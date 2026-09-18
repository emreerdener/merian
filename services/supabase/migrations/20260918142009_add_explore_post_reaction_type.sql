-- Enum values must commit before the following migration uses them.
ALTER TYPE public.explore_notification_type ADD VALUE 'post_reaction';
