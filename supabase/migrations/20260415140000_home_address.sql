-- Add optional home address fields to profiles so customers can
-- prefill their pickup location automatically.

alter table public.profiles
  add column if not exists home_address text,
  add column if not exists home_lat double precision,
  add column if not exists home_lng double precision;
