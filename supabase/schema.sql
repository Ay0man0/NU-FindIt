-- NU FindIt initial Supabase schema
-- Run in the Supabase SQL Editor. Review policies with NU IT before production launch.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default 'NU Member',
  role text not null default 'student' check (role in ('student','staff','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  category text not null check (category in ('Bags','Electronics','Keys','IDs & Cards','Bottles','Clothing','Other')),
  location text not null,
  description text not null default '',
  privacy_level text not null default 'normal' check (privacy_level in ('normal','sensitive')),
  status text not null check (status in ('lost','found','matched','returned')),
  image_path text,
  image_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists items_status_created_idx on public.items(status, created_at desc);
create index if not exists items_category_idx on public.items(category);

-- Ownership prompts are private and must never be exposed through the public item feed.
create table if not exists public.item_private_checks (
  item_id uuid primary key references public.items(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  question text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.verification_requests (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  requester_id uuid not null references public.profiles(id) on delete cascade,
  note text not null default '',
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  unique(item_id, requester_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists messages_item_created_idx on public.messages(item_id, created_at);

-- Identity verification -------------------------------------------------------
-- nu_directory = the official list of real NU members (NU ID + university email).
-- Ask the registrar / NU IT for an export and import it (Table Editor > Import CSV).
-- RLS is enabled with NO policies, so the app can never read or list it.
create table if not exists public.nu_directory (
  nu_id text primary key,
  email text not null unique,
  full_name text,
  created_at timestamptz not null default now()
);
alter table public.nu_directory enable row level security;

-- Each verified account's NU ID. Unique: one NU ID can only ever back one account.
create table if not exists public.student_identities (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nu_id text not null unique,
  verified_at timestamptz not null default now()
);
alter table public.student_identities enable row level security;
drop policy if exists "Users read own identity" on public.student_identities;
create policy "Users read own identity" on public.student_identities for select to authenticated using (auth.uid()=user_id);

-- Server-side enforcement: an account can only be created if the NU ID and email match
-- a row in nu_directory. This cannot be bypassed by editing the front end.
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_nu_id text := nullif(trim(new.raw_user_meta_data->>'nu_id'),'');
  v_name text;
begin
  select d.full_name into v_name from public.nu_directory d
   where d.nu_id = v_nu_id and lower(d.email) = lower(new.email);
  if not found then
    raise exception 'NU_ID_NOT_VERIFIED';
  end if;
  insert into public.profiles(id, full_name)
    values (new.id, coalesce(v_name, new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)))
    on conflict (id) do nothing;
  insert into public.student_identities(user_id, nu_id) values (new.id, v_nu_id);
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.items enable row level security;
alter table public.item_private_checks enable row level security;
alter table public.verification_requests enable row level security;
alter table public.messages enable row level security;

-- Profiles: users can read basic profile data and update only their own name.
drop policy if exists "Profiles visible to signed in users" on public.profiles;
create policy "Profiles visible to signed in users" on public.profiles for select to authenticated using (true);
drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile" on public.profiles for update to authenticated using (auth.uid()=id) with check (auth.uid()=id);
-- Prevent self-service role escalation; only full_name is user-editable.
revoke update on public.profiles from authenticated;
grant update(full_name) on public.profiles to authenticated;

-- Items: authenticated campus users can browse; only owners can create/update/delete their own reports.
drop policy if exists "Authenticated users browse items" on public.items;
create policy "Authenticated users browse items" on public.items for select to authenticated using (true);
drop policy if exists "Users create own items" on public.items;
create policy "Users create own items" on public.items for insert to authenticated with check (auth.uid()=user_id);
drop policy if exists "Owners update own items" on public.items;
create policy "Owners update own items" on public.items for update to authenticated using (auth.uid()=user_id) with check (auth.uid()=user_id);
drop policy if exists "Owners delete own items" on public.items;
create policy "Owners delete own items" on public.items for delete to authenticated using (auth.uid()=user_id);

-- Only the item owner can read or create the private ownership prompt.
drop policy if exists "Owners manage private item checks" on public.item_private_checks;
create policy "Owners manage private item checks" on public.item_private_checks for all to authenticated using (auth.uid()=owner_id) with check (auth.uid()=owner_id and exists(select 1 from public.items i where i.id=item_id and i.user_id=auth.uid()));

-- Verification requests: requester creates/reads their request; item owner can read and decide.
drop policy if exists "Requester or owner reads requests" on public.verification_requests;
create policy "Requester or owner reads requests" on public.verification_requests for select to authenticated using (auth.uid()=requester_id or exists(select 1 from public.items i where i.id=item_id and i.user_id=auth.uid()));
drop policy if exists "Users create own verification requests" on public.verification_requests;
create policy "Users create own verification requests" on public.verification_requests for insert to authenticated with check (auth.uid()=requester_id and exists(select 1 from public.items i where i.id=item_id and i.user_id<>auth.uid()));
drop policy if exists "Owners decide requests" on public.verification_requests;
create policy "Owners decide requests" on public.verification_requests for update to authenticated using (exists(select 1 from public.items i where i.id=item_id and i.user_id=auth.uid())) with check (exists(select 1 from public.items i where i.id=item_id and i.user_id=auth.uid()));

-- Chat is allowed only after the item's owner approves a request.
drop policy if exists "Approved participants read messages" on public.messages;
create policy "Approved participants read messages" on public.messages for select to authenticated using (exists(select 1 from public.verification_requests r join public.items i on i.id=r.item_id where r.item_id=messages.item_id and r.status='approved' and (r.requester_id=auth.uid() or i.user_id=auth.uid())));
drop policy if exists "Approved participants send messages" on public.messages;
create policy "Approved participants send messages" on public.messages for insert to authenticated with check (sender_id=auth.uid() and exists(select 1 from public.verification_requests r join public.items i on i.id=r.item_id where r.item_id=messages.item_id and r.status='approved' and (r.requester_id=auth.uid() or i.user_id=auth.uid())));

-- Public item photo bucket. Do not upload ID cards, faces, or documents containing personal information.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('item-photos','item-photos',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=true, file_size_limit=5242880, allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists "Signed in users upload item photos" on storage.objects;
create policy "Signed in users upload item photos" on storage.objects for insert to authenticated with check (bucket_id='item-photos' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Anyone reads public item photos" on storage.objects;
create policy "Anyone reads public item photos" on storage.objects for select using (bucket_id='item-photos');
drop policy if exists "Owners delete own item photos" on storage.objects;
create policy "Owners delete own item photos" on storage.objects for delete to authenticated using (bucket_id='item-photos' and (storage.foldername(name))[1]=auth.uid()::text);

-- Enable Supabase Realtime for collaborative updates (safe to re-run).
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='items') then
    alter publication supabase_realtime add table public.items;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='messages') then
    alter publication supabase_realtime add table public.messages;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='verification_requests') then
    alter publication supabase_realtime add table public.verification_requests;
  end if;
end $$;
