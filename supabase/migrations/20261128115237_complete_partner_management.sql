create function bdg_private.staff_link_partner_admin(p_partner_id uuid, p_email text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  candidate public.profiles%rowtype;
begin
  if actor is null or public.current_role() is null
     or public.current_role() not in ('owner', 'admin_owner') then
    raise exception 'Akses ditolak';
  end if;
  if nullif(btrim(p_email), '') is null then raise exception 'Email wajib diisi'; end if;
  select p.* into candidate
  from public.profiles p join auth.users u on u.id = p.id
  where lower(u.email) = lower(btrim(p_email)) and u.email_confirmed_at is not null
    and p.role in ('driver', 'partner_admin')
  for update of p;
  if not found then raise exception 'Akun yang sesuai belum terdaftar atau belum mengonfirmasi email'; end if;
  if exists (select 1 from public.partner_users where user_id = candidate.id and partner_id <> p_partner_id)
     or exists (select 1 from public.partners where created_by = candidate.id and id <> p_partner_id) then
    raise exception 'Akun sudah terhubung dengan Mitra lain';
  end if;
  if candidate.role = 'driver' then
    if exists (select 1 from public.driver_claims where user_id = candidate.id and status = 'pending')
       or exists (
         select 1 from public.drivers d
         where d.user_id = candidate.id and (
           exists (select 1 from public.visits v where v.driver_id = d.id)
           or exists (select 1 from public.bookings b where b.driver_id = d.id)
         )
       ) then
      raise exception 'Gunakan akun terpisah. Akun ini memiliki aktivitas atau klaim Driver';
    end if;
  end if;
  perform 1 from public.partners where id = p_partner_id and status in ('pending','approved','suspended') for share;
  if not found then raise exception 'Profil Mitra tidak tersedia'; end if;
  if candidate.role = 'driver' then
    perform public.assign_partner_admin(candidate.id);
  end if;
  insert into public.partner_users(partner_id, user_id, role, created_by)
  values (p_partner_id, candidate.id, 'partner_admin', actor)
  on conflict (partner_id, user_id) do update set role = excluded.role
    where partner_users.role is distinct from excluded.role;
  if found then
    insert into public.audit_logs(actor_id, partner_id, action, target_table, target_id)
    values (actor, p_partner_id, 'link_partner_admin', 'profiles', candidate.id);
  end if;
end;
$$;

create function bdg_private.owner_reactivate_partner(p_partner_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or public.current_role() is distinct from 'owner' then
    raise exception 'Hanya Owner yang dapat mengaktifkan kembali Mitra';
  end if;
  update public.partners set status = 'approved', updated_at = now()
  where id = p_partner_id and status = 'suspended';
  if not found then raise exception 'Mitra tidak ditemukan atau sedang aktif'; end if;
  insert into public.audit_logs(actor_id, partner_id, action, target_table, target_id, old_data, new_data)
  values (auth.uid(), p_partner_id, 'change_partner_status', 'partners', p_partner_id,
          '{"status":"suspended"}', '{"status":"approved"}');
end;
$$;

-- An account created through public signup can have an automatically
-- generated Driver row even when the account is intended to manage a Mitra.
-- Keep that row and prevent new visits from being assigned to it.
create function bdg_private.validate_visit_driver_role()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  driver_role text;
begin
  select p.role into driver_role from public.drivers d
  join public.profiles p on p.id = d.user_id
  where d.id = new.driver_id
  for share of p;
  if driver_role = 'partner_admin' then
    raise exception 'Akun tersebut digunakan untuk mengelola Mitra';
  end if;
  return new;
end;
$$;

revoke all on function bdg_private.validate_visit_driver_role() from public, anon, authenticated;
create trigger validate_visit_driver_role
before insert or update of driver_id on public.visits
for each row execute function bdg_private.validate_visit_driver_role();

CREATE FUNCTION bdg_private.search_drivers(p_partner_id uuid, p_keyword text)
 RETURNS TABLE(driver_id uuid, name text, phone text, kabupaten text, vehicle_type text, plate_no text, status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_user_id uuid;
    v_keyword text;
    v_phone text;
    v_result_count integer;
BEGIN

    v_user_id := (SELECT auth.uid());
    v_keyword := btrim(COALESCE(p_keyword, ''));

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Silakan login terlebih dahulu';
    END IF;

    IF public.current_role()
        IS DISTINCT FROM 'partner_admin' THEN
        RAISE EXCEPTION 'Akses pencarian tidak diizinkan';
    END IF;

    IF NOT public.is_partner_admin(p_partner_id) THEN
        RAISE EXCEPTION 'Anda bukan Admin Mitra ini';
    END IF;

    PERFORM 1
    FROM public.partners p
    WHERE p.id = p_partner_id
      AND p.status = 'approved'
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Mitra belum aktif';
    END IF;

    IF char_length(v_keyword) < 3
       OR char_length(v_keyword) > 100 THEN
        RAISE EXCEPTION
            'Kata kunci harus antara 3 dan 100 karakter';
    END IF;

    v_phone := regexp_replace(
        regexp_replace(v_keyword, '[^0-9]', '', 'g'),
        '^0', '62'
    );

    RETURN QUERY
    SELECT
        d.id,
        d.name,
        d.phone,
        d.kabupaten,
        d.vehicle_type,
        d.plate_no,
        d.status
    FROM public.drivers d
    WHERE d.status IN ('Aktif', 'Tidak Aktif')
      AND NOT EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = d.user_id AND p.role = 'partner_admin'
      )
      AND (
          strpos(lower(d.name), lower(v_keyword)) > 0
          OR (
              char_length(v_phone) >= 3
              AND strpos(
                  regexp_replace(
                      regexp_replace(
                          d.phone, '[^0-9]', '', 'g'
                      ),
                      '^0', '62'
                  ),
                  v_phone
              ) > 0
          )
      )
    ORDER BY d.name, d.id
    LIMIT 20;

    GET DIAGNOSTICS v_result_count = ROW_COUNT;

    INSERT INTO public.audit_logs (
        actor_id,
        partner_id,
        action,
        target_table,
        new_data
    )
    VALUES (
        v_user_id,
        p_partner_id,
        'search_drivers',
        'drivers',
        jsonb_build_object(
            'search_type',
            CASE
                WHEN char_length(v_phone) >= 3
                THEN 'name_or_phone'
                ELSE 'name'
            END,
            'result_count', v_result_count
        )
    );

END;
$function$
;


revoke all on function bdg_private.staff_link_partner_admin(uuid,text), bdg_private.owner_reactivate_partner(uuid),
  bdg_private.search_drivers(uuid,text) from public, anon, authenticated;
grant execute on function bdg_private.staff_link_partner_admin(uuid,text), bdg_private.owner_reactivate_partner(uuid),
  bdg_private.search_drivers(uuid,text) to authenticated;

create function public.staff_link_partner_admin(p_partner_id uuid, p_email text)
returns void
language sql security invoker
set search_path = ''
as $$ select bdg_private.staff_link_partner_admin(p_partner_id, p_email); $$;

create function public.owner_reactivate_partner(p_partner_id uuid)
returns void
language sql security invoker
set search_path = ''
as $$ select bdg_private.owner_reactivate_partner(p_partner_id); $$;

create or replace function public.search_drivers(p_partner_id uuid, p_keyword text)
returns table(driver_id uuid, name text, phone text, kabupaten text, vehicle_type text, plate_no text, status text)
language sql security invoker
set search_path = ''
as $$ select * from bdg_private.search_drivers(p_partner_id, p_keyword); $$;

revoke all on function public.staff_link_partner_admin(uuid,text), public.owner_reactivate_partner(uuid)
  from public, anon, authenticated;
grant execute on function public.staff_link_partner_admin(uuid,text), public.owner_reactivate_partner(uuid)
  to authenticated;
