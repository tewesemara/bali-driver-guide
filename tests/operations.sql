\set ON_ERROR_STOP on
-- Run as postgres in an isolated database with the current schema and migration.
begin;

create function pg_temp.check_result(ok boolean, label text) returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception 'FAILED: %', label; end if;
end;
$$;
create function pg_temp.denied(statement text, expected text) returns void language plpgsql as $$
begin
  execute statement;
  raise exception 'UNEXPECTED SUCCESS: %', statement;
exception when others then
  if position(expected in sqlerrm) = 0 then raise; end if;
end;
$$;
grant execute on function pg_temp.check_result(boolean,text), pg_temp.denied(text,text) to authenticated, anon;

insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000001','owner@example.test','{"full_name":"Owner","whatsapp":"081234500001"}'),
 ('00000000-0000-0000-0000-000000000002','staff@example.test','{"full_name":"Admin Owner","whatsapp":"081234500002"}'),
 ('00000000-0000-0000-0000-000000000003','partner1@example.test','{"full_name":"Admin Mitra A","whatsapp":"081234500003"}'),
 ('00000000-0000-0000-0000-000000000004','partner2@example.test','{"full_name":"Admin Mitra B","whatsapp":"081234500004"}'),
 ('00000000-0000-0000-0000-000000000005','driver@example.test','{"full_name":"Driver","whatsapp":"+62 812-3450-0005"}');
insert into auth.users(id,email,raw_user_meta_data,email_confirmed_at)
values ('00000000-0000-0000-0000-000000000006','other@example.test','{"full_name":"Other","whatsapp":"081234500006"}',now());
select pg_temp.check_result(exists(select 1 from public.drivers where user_id='00000000-0000-0000-0000-000000000006'), 'already-confirmed signup');
update public.profiles set role = case right(id::text, 1)
  when '1' then 'owner' when '2' then 'admin_owner' else 'partner_admin' end
where right(id::text, 1) in ('1','2','3','4');
insert into public.partners(id,name,status) values
 ('10000000-0000-0000-0000-000000000001','Mitra A','approved'),
 ('10000000-0000-0000-0000-000000000002','Mitra B','approved');
insert into public.partner_users(partner_id,user_id,role) values
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003','partner_admin'),
 ('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000004','partner_admin');
insert into public.drivers(id,name,phone,address) values
 ('20000000-0000-0000-0000-000000000005','Driver Impor','081234500005','Alamat lama');
update auth.users set email_confirmed_at = now() where id='00000000-0000-0000-0000-000000000005';
select pg_temp.check_result((select status='pending' from public.driver_claims), 'existing data requires a claim');
select id as claim_id from public.driver_claims \gset

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select pg_temp.check_result((select claimant_email = 'driver@example.test' from public.list_driver_claim_review()), 'staff claim details');
select pg_temp.check_result((select inserted=1 and skipped=1 from public.import_drivers(
  '[{"name":"Duplikat","phone":"+6281234500005"},{"name":"Baru","phone":"081234500007"}]','skip')), 'import skip');
select pg_temp.check_result((select updated=1 from public.import_drivers(
  '[{"name":"Driver Baru","phone":"6281234500005"}]','update')), 'import update');
select pg_temp.check_result((select address='Alamat lama' and user_id is null from public.drivers
  where id='20000000-0000-0000-0000-000000000005'), 'import preserves omitted fields and account link');
select pg_temp.denied($query$select public.import_drivers(
  '[{"name":"Rolled back","phone":"081234500008"},{"name":"","phone":"081234500009"}]','skip')$query$,
  'Nama dan WhatsApp wajib diisi');
select pg_temp.check_result(not exists(select 1 from public.drivers where phone='6281234500008'), 'batch rollback');
select pg_temp.denied($query$select public.owner_assign_admin_owner('00000000-0000-0000-0000-000000000006')$query$, 'Owner');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
select pg_temp.check_result((select count(*)=1 from public.partners), 'partner profile RLS');
select pg_temp.check_result((select count(*)=0 from public.list_driver_claim_review()), 'claim review private');
select pg_temp.denied(format('select public.approve_driver_claim(%L)', :'claim_id'), 'izin');
select pg_temp.denied($query$select public.import_drivers('[{"name":"Other","phone":"081234500008"}]','update')$query$, 'Akses ditolak');
select pg_temp.denied($query$select public.search_drivers('10000000-0000-0000-0000-000000000002','Driver')$query$, 'bukan Admin');
select pg_temp.check_result((select count(*)=1 from public.search_drivers('10000000-0000-0000-0000-000000000001','Driver Baru')), 'scoped search');
select pg_temp.denied($query$select public.update_partner_profile('10000000-0000-0000-0000-000000000002','Wrong',null,null,null,null,null)$query$, 'izin');
select pg_temp.denied($query$select * from public.activity_report(2026,'month','10000000-0000-0000-0000-000000000002')$query$, 'Akses ditolak');
select pg_temp.denied($query$select * from public.activity_report(2026,'month')$query$, 'Akses ditolak');
select * from public.record_visit_and_commission('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000005',3,'Asal','Hotel',100000,null) \gset
select public.request_commission_correction(:'commission_id',110000,'Koreksi sebelum pembayaran');
select public.approve_commission(:'commission_id');
select public.pay_commission(:'commission_id',null);
select public.request_commission_correction(:'commission_id',120000,'Koreksi lunas pertama') as correction_id \gset
select pg_temp.check_result((public.list_commission_management()->0->>'linked')::boolean is false, 'unlinked recipient notification data');
select pg_temp.denied(format('select public.request_commission_correction(%L,130000,%L)', :'commission_id','Tumpang tindih'), 'menunggu');
select pg_temp.denied(format('select public.decide_commission_correction(%L,true)', :'correction_id'), 'Akses ditolak');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',true);
select pg_temp.check_result((select count(*)=0 from public.visits), 'cross-partner visit RLS');
select pg_temp.check_result((select count(*)=0 from public.commission_records), 'cross-partner commission RLS');
select pg_temp.check_result(jsonb_array_length(public.list_commission_management())=0, 'cross-partner commission RPC');
select pg_temp.denied(format('select public.request_commission_correction(%L,130000,%L)', :'commission_id','Mitra lain'), 'Akses ditolak');
select pg_temp.denied($query$select public.record_visit_and_commission('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000005',3,'Asal','Hotel',100000,null)$query$, 'tidak memiliki akses');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select public.approve_driver_claim(:'claim_id');
select pg_temp.check_result((select status='approved' from public.list_driver_claim_review()), 'staff approval');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000006',true);
select pg_temp.denied(format('select public.decide_commission_correction(%L,true)', :'correction_id'), 'Akses ditolak');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',true);
select pg_temp.check_result((select status='approved' from public.driver_claims), 'driver sees own claim');
select pg_temp.check_result(jsonb_array_length(public.list_commission_management())=1, 'linked recipient sees commission');
select public.decide_commission_correction(:'correction_id',true);
select pg_temp.denied(format('select public.decide_commission_correction(%L,true)', :'correction_id'), 'Pengajuan tidak tersedia');
select pg_temp.denied($query$select * from public.activity_report(2026,'month')$query$, 'Akses ditolak');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
select public.request_commission_correction(:'commission_id',110000,'Kembali ke nominal awal') as second_id \gset
select pg_temp.check_result(exists(select 1 from jsonb_array_elements(public.list_commission_management()->0->'corrections') r
    where r->>'id'=:'second_id' and (r->>'old_amount')::numeric=120000), 'successive correction uses effective amount');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',true);
select public.decide_commission_correction(:'second_id',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
select pg_temp.check_result((select visits=1 and guests=3 and commission=120000 and paid=110000
  from public.activity_report(extract(year from now() at time zone 'Asia/Makassar')::integer,'month','10000000-0000-0000-0000-000000000001')), 'monthly totals preserve payment amount');
select pg_temp.check_result((select count(*)=1 from public.activity_report(extract(year from now() at time zone 'Asia/Makassar')::integer,'day','10000000-0000-0000-0000-000000000001')), 'daily report');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
select pg_temp.check_result((select count(*)=1 from public.activity_report(extract(year from now() at time zone 'Asia/Makassar')::integer,'year')), 'owner yearly report');
select pg_temp.check_result((select amount=110000 and status='paid' from public.commission_records), 'payment remains intact');

-- Partner administration uses verified, dedicated accounts and preserves Owner access.
select pg_temp.denied($query$select public.staff_link_partner_admin('10000000-0000-0000-0000-000000000002','owner@example.test')$query$, 'belum terdaftar');
select pg_temp.denied($query$select public.staff_link_partner_admin('10000000-0000-0000-0000-000000000002','driver@example.test')$query$, 'aktivitas atau klaim Driver');
select public.owner_change_partner_status('10000000-0000-0000-0000-000000000002','suspended');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select pg_temp.denied($query$select public.owner_reactivate_partner('10000000-0000-0000-0000-000000000002')$query$, 'Hanya Owner');
select public.staff_link_partner_admin('10000000-0000-0000-0000-000000000002','other@example.test');
select public.staff_link_partner_admin('10000000-0000-0000-0000-000000000002','other@example.test');
select pg_temp.denied($query$select public.staff_link_partner_admin('10000000-0000-0000-0000-000000000001','other@example.test')$query$, 'Mitra lain');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
select public.owner_reactivate_partner('10000000-0000-0000-0000-000000000002');
select pg_temp.check_result((select role='owner' from public.profiles where id=auth.uid()), 'Owner role preserved');
select pg_temp.check_result((select count(*)=1 from public.audit_logs where action='link_partner_admin'), 'idempotent membership and audit');
select id as promoted_driver_id from public.drivers where user_id='00000000-0000-0000-0000-000000000006' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000006',true);
select pg_temp.check_result(public.current_role()='partner_admin' and
  public.is_partner_admin('10000000-0000-0000-0000-000000000002'), 'verified account membership');
select pg_temp.check_result((select count(*)=0 from public.search_drivers('10000000-0000-0000-0000-000000000002','Other')), 'Partner role hidden from Driver search');
select pg_temp.denied(format($query$select public.record_visit_and_commission(
  '10000000-0000-0000-0000-000000000002',%L,3,'Asal','Hotel',100000,null)$query$, :'promoted_driver_id'), 'digunakan untuk mengelola Mitra');

-- Exercise the remaining onboarding and review transitions with dedicated fixtures.
reset role;
insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000007','candidate@example.test','{"full_name":"Candidate","whatsapp":"081234500011"}'),
 ('00000000-0000-0000-0000-000000000008','newpartner@example.test','{"full_name":"Mitra Baru","whatsapp":"081234500012"}'),
 ('00000000-0000-0000-0000-000000000009','rejected@example.test','{"full_name":"Ditolak","whatsapp":"081234500013"}');
insert into public.drivers(name,phone) values ('Existing Driver','081234500013');
update auth.users set email_confirmed_at=now()
where id='00000000-0000-0000-0000-000000000009';
select id as reject_id from public.driver_claims
where user_id='00000000-0000-0000-0000-000000000009' \gset
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
select public.owner_assign_admin_owner('00000000-0000-0000-0000-000000000007');
select pg_temp.check_result((select role='admin_owner' from public.profiles where id='00000000-0000-0000-0000-000000000007'), 'Owner appoints Admin Owner');
select public.assign_partner_admin('00000000-0000-0000-0000-000000000008');
select public.staff_register_partner('Created By Staff',null,null,null,null,null) as staff_partner_id \gset
select public.owner_change_partner_status(:'staff_partner_id','rejected');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000008',true);
select public.register_partner('Pendaftaran Mitra') as self_partner_id \gset
select pg_temp.check_result(public.is_partner_member(:'self_partner_id'), 'self-registration creates membership');
select public.update_partner_profile(:'self_partner_id','Profil diperbarui',null,null,null,null,null);
select pg_temp.check_result((select name='Profil diperbarui' from public.partners where id=:'self_partner_id'), 'own partner edit');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select public.approve_partner(:'self_partner_id');
select public.reject_driver_claim(:'reject_id','Verifikasi identitas gagal');
select pg_temp.check_result((select status='rejected' from public.list_driver_claim_review() where id=:'reject_id'), 'staff rejects claim');
select pg_temp.check_result((select count(*)=1 from public.audit_logs where action='reject_driver_claim' and target_id=:'reject_id'), 'claim outcome audited');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000009',true);
select pg_temp.check_result((select notes='Verifikasi identitas gagal' from public.driver_claims), 'Driver sees rejection reason');
select pg_temp.check_result(public.normalize_whatsapp('+62 812-3450-0013')='6281234500013', 'canonical WhatsApp');
select pg_temp.denied($query$select public.normalize_whatsapp('abc081234500013')$query$, 'tidak valid');

set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.denied($query$select * from public.activity_report(2026,'month')$query$, 'permission denied');
select pg_temp.denied($query$select * from public.list_driver_claim_review()$query$, 'permission denied');
select pg_temp.denied($query$select * from public.import_drivers('[]','skip')$query$, 'permission denied');
rollback;
