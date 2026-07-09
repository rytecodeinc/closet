-- Migration: Add style_tags to user_profiles (text array, max 3 enforced in app).
-- Run in Supabase SQL Editor.

ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS style_tags text[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN public.user_profiles.style_tags IS
  'Up to 3 profile style labels (e.g. Minimalist, Vintage). Validated in app.';
