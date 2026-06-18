// ═══════════════════════════════════════════════════════════════════════════
// endpoint-pro — OpenWrt Terminal CLI Client (CelcomDigi Demo)
// ═══════════════════════════════════════════════════════════════════════════

const axios = require("axios");
const readline = require("readline");

// ─── Config ───────────────────────────────────────────────────────────────
const API_BASE = "https://syncbyte.giize.com";

// Setup readline interface untuk input terminal
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

// Sesi Global menggantikan userState Telegram
let session = {
  msisdn: "",
  cookie: "",
  display: "",
  addons: [],
  offers: [],
  extendOpts: []
};

// ─── Helper: Prompter ─────────────────────────────────────────────────────
function ask(question) {
  return new Promise((resolve) => rl.question(question, resolve));
}

function fmtNum(n) {
  if (n == null) return "0";
  return Number(n).toLocaleString("ms-MY");
}

function parseAddonsData(data) {
  const result = [];
  if (!data || typeof data !== "object") return result;
  Object.keys(data).forEach(k => {
    const cat = data[k];
    if (cat && Array.isArray(cat.products)) {
      cat.products.forEach(p => result.push(p));
    } else if (Array.isArray(cat)) {
      cat.forEach(p => result.push(p));
    }
  });
  return result;
}

// ─── Main Logic ───────────────────────────────────────────────────────────
async function main() {
  console.clear();
  console.log("=======================================");
  console.log("⚡ Endpoint-Pro OpenWrt CLI Client ⚡");
  console.log("=======================================");
  
  if (!session.cookie) {
    await doLoginFlow();
  } else {
    await showMainMenu();
  }
}

// ─── Flow: Login & OTP ────────────────────────────────────────────────────
async function doLoginFlow() {
  console.log("\n[!] Sila log masuk akaun CelcomDigi anda.");
  let phone = await ask("📱 Masukkan nombor telefon (cth: 0123456789): ");
  phone = phone.replace(/\D/g, "");

  if (phone.length < 10) {
    console.log("❌ Nombor tidak sah. Sila mulakan semula.");
    return setTimeout(doLoginFlow, 1500);
  }

  console.log("⏳ Menghantar OTP...");
  try {
    const res = await axios.post(`${API_BASE}/otp/pro`, { msisdn: phone });
    if (res.data.success) {
      console.log("✅ OTP berjaya dihantar!");
      
      const otp = await ask("🔑 Masukkan kod OTP yang diterima: ");
      console.log("⏳ Mengesahkan OTP...");
      
      const loginRes = await axios.post(`${API_BASE}/login/pro`, {
        msisdn: phone,
        otp: otp.trim(),
      });

      if (loginRes.data.success && loginRes.data.cookie) {
        session.cookie = loginRes.data.cookie;
        session.msisdn = phone;
        session.display = phone.replace(/^60/, "0");
        console.log(`\n✅ Akaun berjaya ditambah: ${session.display}`);
        await pressEnterToContinue();
        await showMainMenu();
      } else {
        throw new Error(loginRes.data.error || "OTP salah");
      }
    } else {
      throw new Error(res.data.error || "Gagal hantar OTP");
    }
  } catch (e) {
    console.log(`\n❌ Gagal: ${e.response?.data?.error || e.message}`);
    await pressEnterToContinue();
    return doLoginFlow();
  }
}

// ─── Menu Utama ───────────────────────────────────────────────────────────
async function showMainMenu() {
  console.clear();
  console.log("=======================================");
  console.log(`📱 Sesi Aktif: ${session.display}`);
  console.log("=======================================");
  console.log("1. 📊 Lihat Dashboard");
  console.log("2. 🛒 Senarai & Langgan Addon");
  console.log("3. 🎁 Tawaran Khas (CMP)");
  console.log("4. ⏰ Lanjut Validity (Extend)");
  console.log("5. ❌ Log Keluar (Logout)");
  console.log("=======================================");
  
  const choice = await ask("Pilih menu (1-5): ");
  switch (choice.trim()) {
    case "1": await showDashboard(); break;
    case "2": await showAddons(); break;
    case "3": await showOffers(); break;
    case "4": await showExtendOptions(); break;
    case "5": 
      session.cookie = ""; 
      console.log("👋 Log keluar berjaya.");
      await pressEnterToContinue();
      await doLoginFlow();
      break;
    default:
      console.log("❌ Pilihan tidak sah.");
      await sleep(1000);
      await showMainMenu();
  }
}

// ─── Fungsi: Dashboard ────────────────────────────────────────────────────
async function showDashboard() {
  console.clear();
  console.log("⏳ Memuatkan dashboard...");
  try {
    const res = await axios.post(`${API_BASE}/dashboard/pro`, {
      msisdn: session.msisdn,
      cookie: session.cookie,
    });
    if (!res.data.success) throw new Error(res.data.error || "Gagal");
    
    const d = res.data.data;
    console.clear();
    console.log("=======================================");
    console.log(`📊 Dashboard CelcomDigi: ${session.display}`);
    console.log("=======================================");
    console.log(`▪️ Status: ${d.status}`);
    console.log(`▪️ Plan: ${d.planName}`);
    console.log(`▪️ Baki: ${d.balanceText}`);
    console.log(`▪️ Tamat: ${d.terminationDate}`);
    console.log("---------------------------------------");

    if (d.internetPlans && d.internetPlans.length > 0) {
      console.log("📡 Data Plans:");
      d.internetPlans.forEach(p => {
        console.log(`  • ${p.name || "-"} — ${fmtNum(p.remaining)}/${fmtNum(p.total)} ${p.unit || ""}`);
      });
    } else {
      console.log("📡 Tiada data aktif.");
    }
    console.log("---------------------------------------");
    console.log(`🔌 Addon Aktif: ${d.activeAddons?.length || 0}`);
    console.log(`🎁 Tawaran Khas: ${d.cmpOffers?.length || 0}`);
    console.log("=======================================");

  } catch (e) {
    console.log(`\n❌ Gagal memuatkan dashboard: ${e.response?.data?.error || e.message}`);
  }
  await pressEnterToContinue();
  await showMainMenu();
}

// ─── Fungsi: Addons ───────────────────────────────────────────────────────
async function showAddons() {
  console.clear();
  console.log("⏳ Memuatkan senarai addon...");
  try {
    const res = await axios.post(`${API_BASE}/addons/pro`, { cookie: session.cookie });
    if (!res.data.success) throw new Error(res.data.error || "Gagal");
    
    const addons = parseAddonsData(res.data.data);
    if (!addons.length) {
      console.log("❌ Tiada addon tersedia.");
      await pressEnterToContinue();
      return showMainMenu();
    }
    session.addons = addons;

    console.clear();
    console.log("=======================================");
    console.log("🛒 Senarai Addon Internet");
    console.log("=======================================");
    
    addons.forEach((a, idx) => {
      const name = a.preferred_name || a.name || a.passName || `Addon #${idx + 1}`;
      const price = a.price ? `RM${Number(a.price).toFixed(2)}` : (a.price_cent ? `RM${Number(a.price_cent / 100).toFixed(2)}` : "?");
      const quota = a.internet_quota || a.quota || "";
      const valid = a.validity || "";
      console.log(`${idx + 1}. ${name} — ${price} ${quota ? '· ' + quota : ''} ${valid ? '· ' + valid : ''}`);
    });
    console.log("0. ← Kembali ke Menu Utama");
    console.log("=======================================");

    const choice = await ask("Masukkan nombor untuk langgan (atau 0): ");
    const idx = parseInt(choice) - 1;

    if (choice.trim() === "0") return showMainMenu();
    if (isNaN(idx) || !session.addons[idx]) {
      console.log("❌ Pilihan tidak sah.");
      await sleep(1000);
      return showAddons();
    }

    await doSubscribe(session.addons[idx]);
  } catch (e) {
    console.log(`\n❌ Gagal: ${e.response?.data?.error || e.message}`);
    await pressEnterToContinue();
    await showMainMenu();
  }
}

async function doSubscribe(addon) {
  const name = addon.preferred_name || addon.name || addon.passName || "Addon";
  const price = addon.price || (addon.price_cent ? addon.price_cent / 100 : 0);
  
  console.log(`\n⏳ Melanggan ${name}...`);
  try {
    const res = await axios.post(`${API_BASE}/subscribe/pro`, {
      cookie: session.cookie,
      msisdn: session.msisdn,
      id: addon.id || addon.product_id || addon.passTypeId,
      product_id: addon.product_id || addon.id || addon.passTypeId,
      price: price,
      price_cent: addon.price_cent,
      name: name,
      telcoType: addon.telco_type || 1,
    });
    if (res.data.success) {
      console.log(`\n✅ Berjaya: ${res.data.message || "Addon berjaya dilanggan!"}`);
    } else {
      throw new Error(res.data.error || "Gagal");
    }
  } catch (e) {
    console.log(`\n❌ Gagal melanggan: ${e.response?.data?.error || e.message}`);
  }
  await pressEnterToContinue();
  await showMainMenu();
}

// ─── Fungsi: Offers (CMP) ─────────────────────────────────────────────────
async function showOffers() {
  console.clear();
  console.log("⏳ Memuatkan tawaran khas...");
  try {
    const res = await axios.post(`${API_BASE}/offers/pro`, { cookie: session.cookie, msisdn: session.msisdn });
    if (!res.data.success) throw new Error(res.data.error || "Gagal");
    
    const offers = res.data.data || [];
    if (!offers.length) {
      console.log("❌ Tiada tawaran khas buat masa ini.");
      await pressEnterToContinue();
      return showMainMenu();
    }
    session.offers = offers;

    console.clear();
    console.log("=======================================");
    console.log("🎁 Tawaran Khas (CMP)");
    console.log("=======================================");
    offers.forEach((o, idx) => {
      const name = o.name || o.offerName || `Tawaran #${idx + 1}`;
      const price = o.price ? `RM${Number(o.price).toFixed(2)}` : "Percuma";
      console.log(`${idx + 1}. ${name} — ${price}`);
    });
    console.log("0. ← Kembali ke Menu Utama");
    console.log("=======================================");

    const choice = await ask("Masukkan nombor untuk langgan (atau 0): ");
    const idx = parseInt(choice) - 1;

    if (choice.trim() === "0") return showMainMenu();
    if (isNaN(idx) || !session.offers[idx]) {
      console.log("❌ Pilihan tidak sah.");
      await sleep(1000);
      return showOffers();
    }

    await doCmpSubscribe(session.offers[idx]);
  } catch (e) {
    console.log(`\n❌ Gagal: ${e.response?.data?.error || e.message}`);
    await pressEnterToContinue();
    await showMainMenu();
  }
}

async function doCmpSubscribe(offer) {
  const name = offer.name || "Tawaran";
  console.log(`\n⏳ Melanggan ${name}...`);
  try {
    const res = await axios.post(`${API_BASE}/subscribe/pro`, {
      cookie: session.cookie,
      msisdn: session.msisdn,
      isCmpOffer: true,
      campaignId: offer.campaignId,
      keyword: offer.keyword,
      poId: offer.poId,
    });
    if (res.data.success) {
      console.log(`\n✅ Berjaya: ${res.data.message || "Tawaran berjaya dilanggan!"}`);
    } else {
      throw new Error(res.data.error || "Gagal");
    }
  } catch (e) {
    console.log(`\n❌ Gagal melanggan: ${e.response?.data?.error || e.message}`);
  }
  await pressEnterToContinue();
  await showMainMenu();
}

// ─── Fungsi: Extend Options ───────────────────────────────────────────────
async function showExtendOptions() {
  console.clear();
  console.log("⏳ Memuatkan pilihan extend...");
  try {
    const res = await axios.post(`${API_BASE}/extend-options/pro`, { cookie: session.cookie });
    if (!res.data.success) throw new Error(res.data.error || "Gagal");
    
    const opts = res.data.data || [];
    if (!opts.length) {
      console.log("❌ Tiada pilihan extend.");
      await pressEnterToContinue();
      return showMainMenu();
    }
    session.extendOpts = opts;

    console.clear();
    console.log("=======================================");
    console.log("⏰ Pilihan Extend Validity");
    console.log("=======================================");
    opts.forEach((o, idx) => {
      const name = o.name || `${o.days_to_extend} Hari`;
      const amount = o.amount || o.deductionAmount || 0;
      console.log(`${idx + 1}. ${name} — RM${Number(amount).toFixed(2)}`);
    });
    console.log("0. ← Kembali ke Menu Utama");
    console.log("=======================================");

    const choice = await ask("Masukkan nombor untuk extend (atau 0): ");
    const idx = parseInt(choice) - 1;

    if (choice.trim() === "0") return showMainMenu();
    if (isNaN(idx) || !session.extendOpts[idx]) {
      console.log("❌ Pilihan tidak sah.");
      await sleep(1000);
      return showExtendOptions();
    }

    await doExtend(session.extendOpts[idx]);
  } catch (e) {
    console.log(`\n❌ Gagal: ${e.response?.data?.error || e.message}`);
    await pressEnterToContinue();
    await showMainMenu();
  }
}

async function doExtend(opt) {
  const name = opt.name || `${opt.days_to_extend} Hari`;
  const amount = opt.amount || opt.deductionAmount || 5;
  const days = opt.days_to_extend || opt.incrementDays || 30;
  
  console.log(`\n⏳ Melanjut validity ${name}...`);
  try {
    const res = await axios.post(`${API_BASE}/extend/pro`, {
      cookie: session.cookie,
      amount: Number(amount),
      days: Number(days),
    });
    if (res.data.success) {
      console.log(`\n✅ Validity berjaya dilanjutkan! [${name}]`);
    } else {
      throw new Error(res.data.error || "Gagal");
    }
  } catch (e) {
    console.log(`\n❌ Gagal extend: ${e.response?.data?.error || e.message}`);
  }
  await pressEnterToContinue();
  await showMainMenu();
}

// ─── Utility Helpers ──────────────────────────────────────────────────────
function pressEnterToContinue() {
  return new Promise((resolve) => {
    rl.question("\nTekan [Enter] untuk kembali...", () => resolve());
  });
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Run app
main();
