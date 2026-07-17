-- Keep the curated Backyard safari title in sentence case. Existing
-- publications that still use the old default title follow the template,
-- while user-authored publication titles remain untouched.

UPDATE public.field_trip_templates
SET title = 'Backyard safari',
    updated_at = NOW()
WHERE slug = 'backyard_safari';

UPDATE public.field_trip_publications AS publication
SET title = 'Backyard safari',
    updated_at = NOW()
FROM public.field_trip_templates AS template
WHERE publication.template_id = template.id
  AND template.slug = 'backyard_safari'
  AND publication.title = 'Backyard Safari';
