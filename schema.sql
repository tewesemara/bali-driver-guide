-- Bali Driver & Guide v2 schema. Jalankan di Supabase SQL Editor.
create extension if not exists pgcrypto;
create table if not exists public.profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 email text, full_name text, role text not null default 'driver' check(role in ('admin','ops','driver','guide')),
 created_at timestamptz not null default now()
);
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(id,email,full_name,role) values(new.id,new.email,coalesce(new.raw_user_meta_data->>'full_name',''), 'driver') on conflict(id) do nothing; return new; end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();
create or replace function public.current_role() returns text language sql stable security definer set search_path=public as $$
 select role from public.profiles where id=auth.uid()
$$;
create table if not exists public.drivers(
 id uuid primary key default gen_random_uuid(), user_id uuid references auth.users(id) on delete set null,
 name text not null,phone text not null,address text,license_no text,vehicle_type text,plate_no text,vehicle_capacity integer,rate numeric(14,2),
 vehicle_doc_url text,vehicle_doc_expiry date,status text not null default 'Aktif' check(status in ('Aktif','Tidak Aktif')),created_at timestamptz not null default now()
);
create table if not exists public.guides(
 id uuid primary key default gen_random_uuid(),user_id uuid references auth.users(id) on delete set null,
 name text not null,phone text not null,address text,languages text,service_area text,experience_years integer,rate numeric(14,2),
 status text not null default 'Aktif' check(status in ('Aktif','Tidak Aktif')),created_at timestamptz not null default now()
);
create table if not exists public.bookings(
 id uuid primary key default gen_random_uuid(),booking_date date not null,guest_name text not null,guest_phone text,hotel text,destination text,
 driver_id uuid references public.drivers(id) on delete set null,guide_id uuid references public.guides(id) on delete set null,
 guest_count integer,price numeric(14,2),driver_commission numeric(14,2) default 0,guide_commission numeric(14,2) default 0,
 commission_status text not null default 'Belum Dibayar' check(commission_status in ('Belum Dibayar','Dibayar')),
 status text not null default 'Menunggu' check(status in ('Menunggu','Dikonfirmasi','Berjalan','Selesai','Dibatalkan')),
 notes text,created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
alter table public.drivers enable row level security;
alter table public.guides enable row level security;
alter table public.bookings enable row level security;
-- Profiles: user reads own profile; admin can manage all profiles.
drop policy if exists "profile read" on public.profiles;
create policy "profile read" on public.profiles for select to authenticated using (id=auth.uid() or public.current_role()='admin');
drop policy if exists "admin manage profiles" on public.profiles;
create policy "admin manage profiles" on public.profiles for update to authenticated using (public.current_role()='admin') with check (public.current_role()='admin');
-- Driver/guide/ops/admin access.
drop policy if exists "staff read drivers" on public.drivers;
create policy "staff read drivers" on public.drivers for select to authenticated using (
 public.current_role() in ('admin','ops') or user_id=auth.uid() or exists(select 1 from public.bookings b where b.driver_id=drivers.id and b.guide_id in (select id from public.guides where user_id=auth.uid()))
);
drop policy if exists "staff write drivers" on public.drivers;
create policy "staff write drivers" on public.drivers for all to authenticated using (public.current_role() in ('admin','ops')) with check (public.current_role() in ('admin','ops'));
drop policy if exists "staff read guides" on public.guides;
create policy "staff read guides" on public.guides for select to authenticated using (public.current_role() in ('admin','ops') or user_id=auth.uid());
drop policy if exists "staff write guides" on public.guides;
create policy "staff write guides" on public.guides for all to authenticated using (public.current_role() in ('admin','ops')) with check (public.current_role() in ('admin','ops'));
-- Driver/guide can only read bookings assigned to their linked profile. Admin/ops can manage all.
drop policy if exists "booking read assigned" on public.bookings;
create policy "booking read assigned" on public.bookings for select to authenticated using (
 public.current_role() in ('admin','ops') or
 exists(select 1 from public.drivers d where d.id=bookings.driver_id and d.user_id=auth.uid()) or
 exists(select 1 from public.guides g where g.id=bookings.guide_id and g.user_id=auth.uid())
);
drop policy if exists "booking staff write" on public.bookings;
create policy "booking staff write" on public.bookings for all to authenticated using (public.current_role() in ('admin','ops')) with check (public.current_role() in ('admin','ops'));
grant usage on schema public to authenticated;
grant select,update on public.profiles to authenticated;
grant select,insert,update,delete on public.drivers,public.guides,public.bookings to authenticated;
