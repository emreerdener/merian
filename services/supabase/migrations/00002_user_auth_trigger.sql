-- Make email nullable for Ghost Users (Anonymous)
ALTER TABLE public.users ALTER COLUMN email DROP NOT NULL;

-- Automatically create a profile in public.users when a user signs up (including Ghost Users)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id, email)
  VALUES (new.id, new.email);
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Bind the trigger to the Supabase Auth schema
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
