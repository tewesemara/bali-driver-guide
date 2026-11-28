import os
import re
from pathlib import Path
from subprocess import check_output
from playwright.sync_api import sync_playwright, expect

root = Path(__file__).resolve().parents[1]
app_url = os.environ.get("BDG_TEST_URL", "http://127.0.0.1:8765/")
assets = {}
for url in re.findall(r'<script src="(https://[^"]+)"', (root / "index.html").read_text()):
    assets[url] = check_output(["curl", "-fsSL", "--max-time", "25", url])
uid = '00000000-0000-0000-0000-000000000001'
partner = '10000000-0000-0000-0000-000000000001'
visit = '20000000-0000-0000-0000-000000000001'
commission = '30000000-0000-0000-0000-000000000001'
correction = '40000000-0000-0000-0000-000000000001'
errors = []
with sync_playwright() as playwright:
    browser = playwright.chromium.launch(executable_path=os.environ.get('BDG_CHROMIUM'), args=['--no-sandbox'])
    for viewport in [{'width': 1440, 'height': 900}, {'width': 390, 'height': 844}]:
        for role in ['owner', 'admin_owner', 'partner_admin', 'driver']:
            page = browser.new_page(viewport=viewport, accept_downloads=True)
            page.on('pageerror', lambda error: errors.append(str(error)))
            page.on('dialog', lambda dialog: dialog.accept('admin@example.test') if dialog.type == 'prompt' else dialog.accept())
            calls = []
            for url in assets:
                page.route(url, lambda route: route.fulfill(
                    body=assets[route.request.url], headers={'access-control-allow-origin':'*'}, content_type='application/javascript'))
            claim = {'id': uid, 'status': 'pending', 'driver_name': 'Driver Fixture', 'driver_phone':'628123456789',
                     'claimant_name': 'Akun Fixture', 'claimant_email': 'driver@example.test', 'claimant_phone':'628123456789'}
            def api(route):
                request = route.request
                path = request.url.split('?')[0].split('/')[-1]
                calls.append((path, request.post_data_json if request.method == 'POST' else None))
                headers = {'access-control-allow-origin': '*', 'content-range': '0-0/1'}
                if request.method == 'OPTIONS':
                    return route.fulfill(status=204, headers={**headers, 'access-control-allow-methods':'GET,POST,HEAD,OPTIONS', 'access-control-allow-headers':'*'})
                record = {'id': uid, 'email': 'fixture@example.test'}
                if path == 'token':
                    result = {'access_token': 'a.b.c', 'refresh_token': 'refresh', 'token_type': 'bearer', 'expires_in': 3600, 'user': record}
                elif path == 'user':
                    result = record
                elif path == 'profiles':
                    result = {'role': role, 'full_name':'Akun Fixture','whatsapp':'628123456789'}
                elif path == 'list_driver_claim_review':
                    result = [claim]
                elif path == 'approve_driver_claim':
                    claim['status'] = 'approved'
                    result = None
                elif path == 'driver_claims':
                    result = [claim]
                elif path == 'drivers':
                    result = []
                elif path == 'partner_users':
                    result = [{'partner_id':partner}]
                elif path == 'partners':
                    result = {'id':partner,'name':'Mitra Fixture','status':'approved'}
                    if role in ['owner','admin_owner']:
                        result = [result]
                elif path == 'staff_link_partner_admin':
                    result = None
                elif path == 'search_drivers':
                    result = [{'driver_id':uid,'name':'Driver Fixture','phone':'628123456789','status':'Aktif'}]
                elif path == 'record_visit_and_commission':
                    result = [{'visit_id':visit,'commission_id':commission}]
                elif path == 'visits':
                    result = [{'id':visit,'visit_date':'2026-11-28','partners':{'name':'Mitra Fixture'},'drivers':{'name':'Driver Fixture'},'guest_count':3}]
                elif path == 'list_commission_management':
                    result = [{'id':commission,'visit_id':visit,'driver':'Driver Fixture','linked':role=='driver',
                               'partner':'Mitra Fixture','status':'paid','amount':100000,
                               'corrections':[{'id':correction,'old_amount':100000,'new_amount':120000,'status':'pending','reason':'Fixture'}]}]
                elif path == 'activity_report':
                    result = [{'period':'2026-11','visits':1,'guests':3,'commission':120000,'paid':100000}]
                elif path == 'import_drivers':
                    result = [{'inserted':2,'updated':0,'skipped':0}]
                elif path == 'logout':
                    return route.fulfill(status=204, headers=headers)
                else:
                    result = []
                if request.method == 'HEAD':
                    return route.fulfill(status=200, headers=headers)
                route.fulfill(status=200, headers=headers, json=result)
            page.route('https://wssbbcygkikepyhzudvf.supabase.co/**', api)
            page.goto(app_url)
            page.locator('#email').fill('fixture@example.test')
            page.locator('#password').fill('example-password')
            page.locator('#loginButton').click()
            if role in ['owner','admin_owner']:
                expect(page.locator('#staffDashboardTitle')).to_have_text('Dashboard Owner' if role=='owner' else 'Dashboard Admin Owner')
                if role == 'owner':
                    expect(page.locator('#adminOwnerNav')).to_be_visible()
                else:
                    expect(page.locator('#adminOwnerNav')).to_be_hidden()
                page.locator('[data-page="page-partners"]').click()
                page.get_by_role('button', name='Tautkan Admin').click()
                expect(page.locator('#partnerListMessage')).to_contain_text('berhasil ditautkan')
                assert any(name == 'staff_link_partner_admin' and payload['p_partner_id'] == partner
                           for name, payload in calls)
                page.get_by_role('button', name='Klaim Driver').click()
                expect(page.locator('#staffClaims')).to_contain_text('driver@example.test')
                page.get_by_role('button', name='Setujui klaim').click()
                expect(page.locator('#staffClaims')).to_contain_text('Disetujui')
                page.locator('[data-page="page-visits"]').click()
                expect(page.locator('#ownerVisits')).to_contain_text('Driver Fixture')
                page.locator('[data-page="page-reports"]').click()
                report = '#ownerReport'
                page.locator('[data-page="page-drivers"]').click()
                file = page.evaluate("""() => {
                  const wb = XLSX.utils.book_new();
                  const ws = XLSX.utils.aoa_to_sheet([['Nama Driver','WhatsApp'],['A',8123456789],['B','+62 812-3456-7890'],['Invalid','abc']]);
                  XLSX.utils.book_append_sheet(wb,ws,'Drivers');
                  return Array.from(new Uint8Array(XLSX.write(wb,{bookType:'xlsx',type:'array'})));
                }""")
                page.locator('#excelFile').set_input_files({'name':'fixtures.xlsx','mimeType':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','buffer':bytes(file)})
                expect(page.locator('#excelPreview')).to_contain_text('2 data siap diimpor')
                page.get_by_role('button', name='MULAI IMPORT KE DATABASE').click()
                expect(page.locator('#excelPreview')).to_contain_text('Baru: 2')
                assert any(name == 'import_drivers' and payload['p_rows'][0]['phone'] == '628123456789' for name,payload in calls)
                page.locator('[data-page="page-reports"]').click()
            elif role == 'partner_admin':
                expect(page.locator('#mitraVisits')).to_contain_text('Driver Fixture')
                expect(page.locator('#mitraCommissionList')).to_contain_text('Driver belum memiliki akun terhubung')
                page.locator('#mitraKeyword').fill('Driver Fixture')
                page.get_by_role('button', name='Cari Driver').click()
                page.locator('#mitraSearchRows').get_by_role('button').click()
                page.locator('#visitGuestCount').fill('3')
                page.locator('#visitOrigin').fill('Asal')
                page.locator('#visitAccommodation').fill('Hotel')
                page.locator('#visitAmount').fill('120000')
                page.locator('#visitSave').click()
                expect(page.locator('#visitMessage')).to_contain_text('berhasil disimpan')
                assert any(name == 'record_visit_and_commission' and payload['p_partner_id'] == partner
                           for name, payload in calls)
                report = '#mitraReport'
                assert any(name == 'activity_report' and payload['p_partner_id'] == partner for name,payload in calls)
            else:
                expect(page.locator('#driverClaims')).to_contain_text('Menunggu verifikasi')
                page.get_by_role('button', name='Setujui koreksi').click()
                expect(page.locator('#driverCommissionList')).to_contain_text('Driver Fixture')
                assert any(name == 'decide_commission_correction' and payload['p_accept'] for name,payload in calls)
                report = None
            if report:
                page.locator(report+' select').select_option('day')
                expect(page.locator(report)).to_contain_text('120.000')
                with page.expect_download() as info:
                    page.locator(report).get_by_role('button',name='Ekspor Excel').click()
                assert info.value.suggested_filename.startswith('laporan-harian-')
                exported = page.evaluate("""values => {
                    const workbook = XLSX.read(new Uint8Array(values), {type:'array'});
                    return XLSX.utils.sheet_to_json(workbook.Sheets.Aktivitas,{header:1});
                }""", list(Path(info.value.path()).read_bytes()))
                assert exported[1] == ['2026-11',1,3,120000,100000], exported
            assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'), (role,viewport)
            print(role, viewport['width'], 'OK')
            page.close()
    assert not errors, errors
