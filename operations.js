"use strict";

function operationNode(tag, value = "") {
  const node = document.createElement(tag);
  node.textContent = value;
  return node;
}

function operationButton(label, handler) {
  const button = operationNode("button", label);
  button.type = "button";
  button.className = "secondary";
  button.onclick = handler;
  return button;
}

function operationTable(columns, rows) {
  const wrapper = operationNode("div");
  wrapper.className = "table-wrap";
  const table = operationNode("table");
  const header = table.createTHead().insertRow();
  for (const name of columns) {
    const column = operationNode("th", name);
    column.scope = "col";
    header.append(column);
  }
  const body = table.createTBody();
  for (const values of rows) {
    const row = body.insertRow();
    for (const value of values) {
      const cell = row.insertCell();
      if (value instanceof Node) cell.append(value);
      else cell.textContent = value ?? "—";
    }
  }
  wrapper.append(table);
  return wrapper;
}

async function operationPages(buildQuery) {
  const records = [];
  const pageSize = 200;
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await buildQuery().range(offset, offset + pageSize - 1);
    if (error) throw error;
    records.push(...data);
    if (data.length < pageSize) return records;
  }
}

function operationPanel(id, title, render) {
  const root = document.getElementById(id);
  const controls = operationNode("div");
  const status = operationNode("p");
  status.setAttribute("role", "status");
  const content = operationNode("div");
  content.className = "operational-content";
  let generation = 0;

  function clear() {
    generation++;
    status.textContent = "";
    content.replaceChildren();
  }

  async function reload() {
    clear();
    const request = generation;
    const role = window.currentRole;
    const current = () => request === generation && role === window.currentRole;
    status.textContent = "Memuat…";
    try {
      const result = await render(reload, current, status);
      if (!current()) return;
      content.append(result);
      status.textContent = "";
    } catch (error) {
      if (current()) status.textContent = "Gagal memuat. " + error.message;
    }
  }

  controls.className = "actions";
  controls.append(operationButton("Muat ulang", reload));
  root.append(operationNode("h3", title), controls, status, content);
  return { clear, reload, controls };
}

function createClaimPanel(id, staff) {
  return operationPanel(id, staff ? "Tinjau klaim akun Driver" : "Status akun Driver", async (reload, current, status) => {
    const claims = await operationPages(() => {
      const query = staff ? db.rpc("list_driver_claim_review") : db.from("driver_claims").select("id,status,created_at,notes");
      return query.order("created_at", { ascending: false }).order("id");
    });
    if (!staff) {
      const { data, error } = await db.from("drivers").select("id").limit(1);
      if (error) throw error;
      if (data.length) return operationNode("p", "Akun sudah terhubung dengan data Driver.");
      if (!claims.length) return operationNode("p", "Akun belum terhubung. Hubungi administrasi untuk memeriksa nomor WhatsApp pendaftaran.");
    }
    if (!claims.length) return operationNode("p", "Belum ada pengajuan.");
    const section = operationNode("div");
    if (staff) section.append(operationNode("p", "Verifikasi identitas pemohon dengan menghubungi nomor pada data Driver sebelum menyetujui klaim."));
    for (const claim of claims) {
      const card = operationNode("article");
      card.className = "card";
      const labels = { pending: "Menunggu verifikasi", approved: "Disetujui", rejected: "Ditolak" };
      card.append(operationNode("strong", labels[claim.status] ?? claim.status));
      if (staff) {
        card.append(
          operationNode("p", "Data Driver · " + (claim.driver_name ?? "—") + " · " + (claim.driver_phone ?? "—")),
          operationNode("p", "Pemohon · " + [claim.claimant_name, claim.claimant_email, claim.claimant_phone].filter(Boolean).join(" · "))
        );
      }
      if (claim.notes) card.append(operationNode("p", claim.notes));
      if (staff && claim.status === "pending") {
        const actions = operationNode("div");
        actions.className = "actions";
        async function decide(accept) {
          if (!current()) return;
          const args = { p_claim_id: claim.id };
          if (accept) {
            if (!confirm("Identitas Driver sudah diverifikasi. Setujui klaim ini?")) return;
          } else {
            const reason = prompt("Alasan penolakan");
            if (!reason?.trim()) return;
            args.p_notes = reason.trim();
          }
          approve.disabled = reject.disabled = true;
          try {
            const { error } = await db.rpc(accept ? "approve_driver_claim" : "reject_driver_claim", args);
            if (error) throw error;
            if (current()) await reload();
          } catch (error) {
            if (current()) status.textContent = error.message;
          } finally {
            approve.disabled = reject.disabled = false;
          }
        }
        const approve = operationButton("Setujui klaim", () => decide(true));
        const reject = operationButton("Tolak klaim", () => decide(false));
        actions.append(approve, reject);
        card.append(actions);
      }
      section.append(card);
    }
    return section;
  });
}

function createVisitPanel(id, partner) {
  return operationPanel(id, "Riwayat kunjungan", async () => {
    if (partner && !mitraId) return operationNode("p", "Riwayat tersedia setelah Mitra terdaftar.");
    const visits = await operationPages(() => {
      let query = db.from("visits")
        .select("id,visit_date,driver_id,guest_count,guest_origin,accommodation,notes,partners(name)" + (partner ? "" : ",drivers(name)"))
        .order("visit_date", { ascending: false }).order("id");
      if (partner) query = query.eq("partner_id", mitraId);
      return query;
    });
    if (!visits.length) return operationNode("p", "Belum ada kunjungan.");
    const names = new Map();
    if (partner) {
      const { data, error } = await db.rpc("list_commission_management");
      if (error) throw error;
      for (const commission of data) names.set(commission.visit_id, commission.driver);
    }
    return operationTable(["Tanggal", "Mitra", "Driver", "Tamu", "Asal", "Menginap", "Catatan"],
      visits.map(v => [v.visit_date, v.partners?.name, partner ? names.get(v.id) : v.drivers?.name,
        v.guest_count, v.guest_origin, v.accommodation, v.notes]));
  });
}

function createReportPanel(id, partner) {
  const periods = { day: "Harian", month: "Bulanan", year: "Tahunan" };
  const period = operationNode("select");
  for (const [value, label] of Object.entries(periods)) {
    const option = operationNode("option", label);
    option.value = value;
    period.append(option);
  }
  period.value = "month";
  const year = operationNode("input");
  year.type = "number";
  year.min = "1900";
  year.max = "9998";
  year.required = true;
  year.value = new Intl.DateTimeFormat("id", { timeZone: "Asia/Makassar", year: "numeric" }).format(new Date());
  const panel = operationPanel(id, "Laporan kunjungan dan komisi", async (_, current, status) => {
    if (partner && !mitraId) return operationNode("p", "Laporan tersedia setelah Mitra terdaftar.");
    if (!year.checkValidity()) throw Error("Masukkan tahun yang valid.");
    const { data, error } = await db.rpc("activity_report", {
      p_year: Number(year.value), p_period: period.value, p_partner_id: partner ? mitraId : null
    });
    if (error) throw error;
    if (!data.length) return operationNode("p", "Belum ada aktivitas pada tahun tersebut.");
    const columns = ["Periode", "Kunjungan", "Tamu", "Komisi disetujui (Rp)", "Pembayaran tercatat (Rp)"];
    const rows = data.map(row => [row.period, Number(row.visits), Number(row.guests),
      Number(row.commission), Number(row.paid)]);
    const max = Math.max(1, ...rows.map(row => row[1]));
    const section = operationNode("div");
    const exportButton = operationButton("Ekspor Excel", () => {
      if (!current()) return;
      if (typeof XLSX === "undefined") {
        status.textContent = "Pustaka Excel gagal dimuat. Muat ulang halaman.";
        return;
      }
      const workbook = XLSX.utils.book_new();
      const sheet = XLSX.utils.aoa_to_sheet([columns, ...rows]);
      sheet["!cols"] = columns.map(label => ({ wch: label.length + 4 }));
      XLSX.utils.book_append_sheet(workbook, sheet, "Aktivitas");
      XLSX.writeFile(workbook, "laporan-" + periods[period.value].toLowerCase() + "-" + year.value + ".xlsx");
    });
    section.append(exportButton, operationTable(columns, rows.map(([date, visits, guests, commission, paid]) => {
      const count = operationNode("div", visits);
      const bar = operationNode("progress");
      bar.className = "report-bar";
      bar.max = max;
      bar.value = visits;
      bar.setAttribute("aria-label", "Jumlah kunjungan " + date);
      count.append(bar);
      return [date, count, guests, formatRupiah(commission), formatRupiah(paid)];
    })));
    return section;
  });
  const periodLabel = operationNode("label", "Periode");
  const yearLabel = operationNode("label", "Tahun");
  periodLabel.append(period);
  yearLabel.append(year);
  period.onchange = year.onchange = panel.reload;
  panel.controls.prepend(periodLabel, yearLabel);
  return panel;
}
