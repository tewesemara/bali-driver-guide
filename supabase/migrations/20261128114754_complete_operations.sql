-- Requires the current Bali Driver & Guide production schema.
-- Apply as one transaction through the migration runner.
create function public.list_driver_claim_review()
returns table(id uuid, status text, created_at timestamptz, notes text,
              driver_name text, driver_phone text, claimant_name text,
              claimant_email text, claimant_phone text)
language sql stable security definer
set search_path = ''
as $$
  select c.id, c.status, c.created_at, c.notes, d.name, d.phone,
         p.full_name, p.email, p.whatsapp
  from public.driver_claims c
  join public.drivers d on d.id = c.driver_id
  join public.profiles p on p.id = c.user_id
  where (select auth.uid()) is not null
    and (select public.current_role()) in ('owner', 'admin_owner');
$$;

-- The originally paid amount remains the payment record. Only an approved
-- correction submitted after payment becomes the effective amount.
create or replace function public.request_commission_correction(
  p_id uuid, p_amount numeric, p_reason text
)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  commission public.commission_records%rowtype;
  effective_amount numeric;
  correction_id uuid;
begin
  if auth.uid() is null or public.current_role() is distinct from 'partner_admin' then
    raise exception 'Akses ditolak';
  end if;
  select * into commission from public.commission_records where id = p_id for update;
  if not found or not public.is_partner_admin(commission.partner_id) then
    raise exception 'Akses ditolak';
  end if;
  perform 1 from public.partners where id = commission.partner_id and status = 'approved' for share;
  if not found then raise exception 'Mitra belum aktif'; end if;
  if commission.status = 'cancelled' then raise exception 'Komisi sudah dibatalkan'; end if;
  effective_amount := commission.amount;
  if commission.status = 'paid' then
    select coalesce((
      select r.new_amount from public.commission_corrections r
      where r.commission_id = p_id and r.status = 'approved'
        and r.requested_at >= commission.paid_at and r.decided_by is not null
      order by r.decided_at desc nulls last, r.id desc limit 1
    ), commission.amount) into effective_amount;
    if exists (select 1 from public.commission_corrections where commission_id = p_id and status = 'pending') then
      raise exception 'Masih ada koreksi yang menunggu keputusan Driver';
    end if;
  end if;
  if p_amount is null or p_amount < 0 or p_amount > 999999999999
     or p_amount <> round(p_amount, 2) or p_amount = effective_amount
     or nullif(btrim(p_reason), '') is null or length(btrim(p_reason)) > 500 then
    raise exception 'Nominal atau alasan koreksi tidak valid';
  end if;
  insert into public.commission_corrections(commission_id, old_amount, new_amount, reason, status, requested_by)
  values (p_id, effective_amount, p_amount, btrim(p_reason),
          case when commission.status = 'paid' then 'pending' else 'approved' end, auth.uid())
  returning id into correction_id;
  if commission.status <> 'paid' then
    update public.commission_records
    set amount = p_amount, status = 'pending', approved_by = null, approved_at = null, updated_at = now()
    where id = p_id;
  end if;
  return correction_id;
end;
$$;

create or replace function public.list_commission_management()
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id, 'visit_id', c.visit_id, 'driver', d.name, 'linked', d.user_id is not null,
    'partner', p.name, 'amount', c.amount, 'status', c.status, 'paid_at', c.paid_at,
    'corrections', coalesce((select jsonb_agg(to_jsonb(r) order by r.requested_at, r.id)
                             from public.commission_corrections r where r.commission_id = c.id), '[]'::jsonb)
  ) order by c.created_at desc, c.id), '[]'::jsonb)
  from public.commission_records c
  join public.drivers d on d.id = c.driver_id
  join public.partners p on p.id = c.partner_id
  where (select auth.uid()) is not null and (
    (select public.current_role()) in ('owner', 'admin_owner')
    or ((select public.current_role()) = 'driver' and d.user_id = (select auth.uid()))
    or ((select public.current_role()) = 'partner_admin'
        and p.status in ('approved', 'suspended') and public.is_partner_admin(c.partner_id))
  );
$$;

create function public.activity_report(p_year integer, p_period text, p_partner_id uuid default null)
returns table(period text, visits bigint, guests bigint, commission numeric, paid numeric)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  actor_role text := public.current_role();
  first_day date;
  last_day date;
begin
  if auth.uid() is null or actor_role is null
     or actor_role not in ('owner', 'admin_owner', 'partner_admin') then
    raise exception 'Akses ditolak';
  end if;
  if actor_role = 'partner_admin' and (p_partner_id is null or not public.is_partner_admin(p_partner_id)) then
    raise exception 'Akses ditolak';
  end if;
  if p_year is null or p_year not between 1900 and 9998
     or p_period is null or p_period not in ('day', 'month', 'year') then
    raise exception 'Periode tidak valid';
  end if;
  first_day := make_date(p_year, 1, 1);
  last_day := make_date(p_year + 1, 1, 1);
  return query
  with scoped_visits as (
    select v.id, v.guest_count, date_trunc(p_period, v.visit_date::timestamp) as bucket
    from public.visits v
    join public.partners p on p.id = v.partner_id
    where v.visit_date >= first_day and v.visit_date < last_day
      and (p_partner_id is null or v.partner_id = p_partner_id)
      and (actor_role <> 'partner_admin' or p.status in ('approved', 'suspended'))
  ), visit_counts as (
    select v.bucket, count(*) as visit_count, sum(v.guest_count) as guest_count
    from scoped_visits v group by v.bucket
  ), amounts as (
    select v.bucket,
           sum(coalesce(r.new_amount, c.amount)) filter (where c.status in ('approved', 'paid')) as total,
           sum(c.amount) filter (where c.status = 'paid') as paid_total
    from scoped_visits v
    join public.commission_records c on c.visit_id = v.id
    left join lateral (
      select correction.new_amount from public.commission_corrections correction
      where c.status = 'paid' and correction.commission_id = c.id and correction.status = 'approved'
        and correction.requested_at >= c.paid_at and correction.decided_by is not null
      order by correction.decided_at desc nulls last, correction.id desc limit 1
    ) r on true
    group by v.bucket
  )
  select to_char(v.bucket, case p_period when 'day' then 'YYYY-MM-DD' when 'month' then 'YYYY-MM' else 'YYYY' end),
         v.visit_count, v.guest_count, coalesce(a.total, 0), coalesce(a.paid_total, 0)
  from visit_counts v left join amounts a using (bucket) order by v.bucket;
end;
$$;

create function public.import_drivers(p_rows jsonb, p_mode text)
returns table(inserted integer, updated integer, skipped integer)
language plpgsql security invoker
set search_path = ''
as $$
declare
  item jsonb;
  phone_number text;
  driver_id uuid;
begin
  if auth.uid() is null or public.current_role() is null
     or public.current_role() not in ('owner', 'admin_owner') then
    raise exception 'Akses ditolak';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array'
     or p_mode is null or p_mode not in ('skip', 'update') then
    raise exception 'Format impor tidak valid';
  end if;
  if jsonb_array_length(p_rows) not between 1 and 50 then
    raise exception 'Jumlah baris per kelompok harus antara 1 dan 50';
  end if;
  inserted := 0;
  updated := 0;
  skipped := 0;
  -- Process in canonical phone order to keep concurrent imports consistent.
  for item in select value from jsonb_array_elements(p_rows)
              order by public.normalize_whatsapp(value->>'phone')
  loop
    phone_number := public.normalize_whatsapp(item->>'phone');
    if phone_number is null or nullif(btrim(item->>'name'), '') is null then
      raise exception 'Nama dan WhatsApp wajib diisi';
    end if;
    insert into public.drivers(name, phone, kabupaten, address, vehicle_type, plate_no, license_no)
    values (btrim(item->>'name'), phone_number, item->>'kabupaten', item->>'address',
            item->>'vehicle_type', item->>'plate_no', item->>'license_no')
    on conflict ((regexp_replace(regexp_replace(phone, '[^0-9]', '', 'g'), '^0', '62')))
    do nothing returning id into driver_id;
    if driver_id is not null then
      inserted := inserted + 1;
    elsif p_mode = 'update' then
      update public.drivers d set name = btrim(item->>'name'), phone = phone_number,
        kabupaten = coalesce(item->>'kabupaten', d.kabupaten),
        address = coalesce(item->>'address', d.address),
        vehicle_type = coalesce(item->>'vehicle_type', d.vehicle_type),
        plate_no = coalesce(item->>'plate_no', d.plate_no),
        license_no = coalesce(item->>'license_no', d.license_no)
      where regexp_replace(regexp_replace(d.phone, '[^0-9]', '', 'g'), '^0', '62') = phone_number;
      if not found then raise exception 'Data berubah selama impor. Ulangi kelompok ini.'; end if;
      updated := updated + 1;
    else
      skipped := skipped + 1;
    end if;
  end loop;
  return next;
end;
$$;

revoke all on function public.list_driver_claim_review(), public.activity_report(integer, text, uuid),
  public.import_drivers(jsonb, text) from public, anon, authenticated;
grant execute on function public.list_driver_claim_review(), public.activity_report(integer, text, uuid),
  public.import_drivers(jsonb, text) to authenticated;

grant execute on function public.normalize_whatsapp(text) to authenticated;

-- INSERT covers signups already confirmed at creation. PostgreSQL runs
-- on_auth_user_created first, so the profile is available to the trigger.
create trigger on_driver_email_confirmed_at_create
after insert on auth.users
for each row when (new.email_confirmed_at is not null)
execute function public.activate_verified_driver();
