-- Update handle_new_user to read role from auth metadata so new users
-- can pick customer vs driver at signup time.

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
declare
  meta_role text;
begin
  meta_role := new.raw_user_meta_data->>'role';
  if meta_role is null or meta_role not in ('customer', 'driver', 'both') then
    meta_role := 'customer';
  end if;

  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    meta_role
  );
  return new;
end;
$$;
