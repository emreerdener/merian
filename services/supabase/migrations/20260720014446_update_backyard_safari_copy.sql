-- Restore the curated title's proper-name capitalization and keep the stored
-- subtitle count-free so clients can insert the viewer's current level target.

UPDATE public.field_trip_templates
SET title = 'Backyard Safari',
    subtitle = 'Observe local species often found in your own backyard.',
    updated_at = NOW()
WHERE slug = 'backyard_safari';

-- Normalize only publications that still carry the previous generated default.
-- User-authored titles remain untouched.
UPDATE public.field_trip_publications AS publication
SET title = 'Backyard Safari',
    updated_at = NOW()
FROM public.field_trip_templates AS template
WHERE publication.template_id = template.id
  AND template.slug = 'backyard_safari'
  AND publication.title = 'Backyard safari';
