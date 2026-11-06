/* State of Deliverance Territorial Lottery - NUI
 * Presentation only. The server has already decided the outcome; this file
 * draws the ticket, lets the player scratch it, and asks the server to settle.
 * Mock mode for development/screenshots: index.html?mock=ticket | admin | telegram
 */
(() => {
  'use strict';

  const params = new URLSearchParams(location.search);
  const MOCK = params.get('mock');
  const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'sod_lottery';
  const $ = (id) => document.getElementById(id);

  const LABELS = {
    SILVER_DOLLAR: 'Silver Dollar', HORSESHOES: 'Horseshoes', COWBOY_HAT: 'Cowboy Hat', TOP_HAT: 'Top Hat', GOLD_NUGGET: 'Gold Nugget',
    MOONSHINE: 'Moonshine Still', OIL_PUMP: 'Oil Pump', TUMBLEWEED: 'Tumbleweed',
  };
  const JACKPOT_SYMBOLS = new Set(['MOONSHINE', 'OIL_PUMP']);

  const money = (n) => {
    n = Math.round((Number(n) || 0) * 100) / 100;
    return '$' + n.toLocaleString('en-US', { minimumFractionDigits: n % 1 ? 2 : 0, maximumFractionDigits: 2 });
  };
  const pct = (n) => (Number.isFinite(n) ? n.toFixed(2) + '%' : '-');
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const sym = (id) => `<svg viewBox="0 0 64 64"><use href="#sym-${esc(id)}"/></svg>`;

  function post(name, data = {}) {
    if (MOCK) { console.log('[mock] post', name, data); return Promise.resolve({ ok: true }); }
    return fetch(`https://${RES}/${name}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data),
    }).then((r) => r.json()).catch(() => ({}));
  }

  // Shared volume for every lottery sound (0 = muted).
  const VOLUME = Math.min(1, Math.max(0, parseFloat(params.get('volume') ?? '0.6')));
  function play(id, vol = 1) {
    const a = $(id);
    if (!a || VOLUME <= 0) return;
    try { a.currentTime = 0; a.volume = VOLUME * vol; const p = a.play(); if (p) p.catch(() => {}); } catch (e) { /* ignore */ }
  }

  /* ======================= Toasts & telegram ======================= */
  function toast({ text, kind = 'info', ms = 6000 }) {
    const el = document.createElement('div');
    el.className = `toast ${kind}`;
    el.textContent = text;
    $('toasts').appendChild(el);
    setTimeout(() => el.remove(), ms);
  }
  let tgTimer = null;
  function telegram({ head, body, sign, ms = 14000 }) {
    $('tg-head').textContent = head || 'WESTERN TERRITORIAL TELEGRAPH CO.';
    $('tg-body').textContent = body || '';
    $('tg-sign').textContent = sign || '';
    $('telegram').classList.remove('hidden');
    clearTimeout(tgTimer);
    tgTimer = setTimeout(() => $('telegram').classList.add('hidden'), ms);
  }

  /* ======================= Scratch ticket ======================= */
  // Compact overlay: 480x360 design size at 1920x1080, scaled with the viewport.
  function fitTicket() {
    const s = Math.max(0.6, Math.min(window.innerWidth / 1920, window.innerHeight / 1080) * 1);
    $('ticket').style.setProperty('--s', s.toFixed(3));
  }
  window.addEventListener('resize', fitTicket);
  fitTicket();

  const T = { serial: null, grid: [], revealed: false, claimed: false, result: null, scratching: false, moves: 0 };
  const foil = $('foil');
  const fctx = foil.getContext('2d', { willReadFrequently: true });

  function paintFoil() {
    const w = foil.width = foil.clientWidth || 318;
    const h = foil.height = foil.clientHeight || 158;
    fctx.globalCompositeOperation = 'source-over';
    const g = fctx.createLinearGradient(0, 0, w, h);
    g.addColorStop(0, '#c9b37a'); g.addColorStop(0.35, '#ece0b4'); g.addColorStop(0.55, '#b4985a'); g.addColorStop(1, '#8c7240');
    fctx.fillStyle = g; fctx.fillRect(0, 0, w, h);
    // engraved guilloche lines
    fctx.strokeStyle = 'rgba(90,64,30,.28)'; fctx.lineWidth = 1;
    for (let i = -h; i < w; i += 9) { fctx.beginPath(); fctx.moveTo(i, 0); fctx.lineTo(i + h, h); fctx.stroke(); }
    fctx.strokeStyle = 'rgba(255,250,220,.22)';
    for (let i = 0; i < w + h; i += 9) { fctx.beginPath(); fctx.moveTo(i, 0); fctx.lineTo(i - h, h); fctx.stroke(); }
    // cell plates
    // one row of three plates
    const cw = w / 3;
    for (let c = 0; c < 3; c++) {
      const x = c * cw + 7, y = 7, pw = cw - 14, ph = h - 14;
      fctx.strokeStyle = 'rgba(60,40,15,.55)'; fctx.lineWidth = 2; fctx.strokeRect(x, y, pw, ph);
      fctx.fillStyle = 'rgba(60,40,15,.65)'; fctx.font = 'bold 26px Georgia'; fctx.textAlign = 'center'; fctx.textBaseline = 'middle';
      fctx.fillText('\u2726', x + pw / 2, y + ph / 2 - 12);
      fctx.font = 'bold 10px Georgia'; fctx.fillText(T.strings.scratch || 'SCRATCH HERE', x + pw / 2, y + ph / 2 + 16);
    }
    foil.style.opacity = 1;
  }

  function scratchAt(x, y) {
    fctx.globalCompositeOperation = 'destination-out';
    fctx.beginPath(); fctx.arc(x, y, 16, 0, Math.PI * 2); fctx.fill();
    // rough edges
    for (let i = 0; i < 4; i++) {
      fctx.beginPath(); fctx.arc(x + (Math.random() - 0.5) * 22, y + (Math.random() - 0.5) * 22, 4 + Math.random() * 5, 0, Math.PI * 2); fctx.fill();
    }
  }

  let last = null;
  let lastScratchSound = 0;
  // Foil-scratch sound: retriggered at most every 330 ms while dragging, so it
  // loops naturally instead of firing on every pointer event.
  function scratchSound() {
    const now = performance.now();
    if (now - lastScratchSound < 330) return;
    lastScratchSound = now;
    play('snd-scratch', 0.7);
  }
  function scratchLine(x, y) {
    scratchSound();
    if (last) {
      const dx = x - last.x, dy = y - last.y, steps = Math.max(1, Math.hypot(dx, dy) / 8);
      for (let i = 1; i <= steps; i++) scratchAt(last.x + dx * i / steps, last.y + dy * i / steps);
    } else scratchAt(x, y);
    last = { x, y };
    if (++T.moves % 15 === 0 && clearedFraction() > 0.62) revealAll();
  }

  function clearedFraction() {
    const { width: w, height: h } = foil;
    const data = fctx.getImageData(0, 0, w, h).data;
    let clear = 0, total = 0;
    for (let i = 3; i < data.length; i += 4 * 16) { total++; if (data[i] < 40) clear++; }
    return clear / total;
  }

  const pos = (e) => { const r = foil.getBoundingClientRect(); return { x: (e.clientX - r.left) * foil.width / r.width, y: (e.clientY - r.top) * foil.height / r.height }; };
  foil.addEventListener('pointerdown', (e) => { if (T.revealed) return; T.scratching = true; last = null; const p = pos(e); scratchLine(p.x, p.y); });
  window.addEventListener('pointerup', () => { T.scratching = false; last = null; });
  foil.addEventListener('pointermove', (e) => { if (!T.scratching || T.revealed) return; const p = pos(e); scratchLine(p.x, p.y); });

  function revealAll() {
    if (T.revealed) return;
    T.revealed = true;
    play('snd-scratch', 0.8);
    foil.style.transition = 'opacity .45s'; foil.style.opacity = 0;
    setTimeout(() => fctx.clearRect(0, 0, foil.width, foil.height), 460);
    $('btn-reveal').disabled = true;
    claim();
  }

  function claim() {
    if (T.claimed) return;
    T.claimed = true;
    $('banner').className = 'banner'; $('banner').innerHTML = `<small>${esc(T.strings.waiting)}</small>`;
    if (MOCK) { setTimeout(() => showResult(mockResult()), 400); return; }
    post('claim', { serial: T.serial });
    // the server always answers (or auto-settles on timeout); let the player leave if it is slow
    setTimeout(() => { if (!T.result) $('btn-close').disabled = false; }, 8000);
  }

  function showResult(r) {
    T.result = r;
    if (!$('ticket-wrap').classList.contains('hidden') && !T.revealed) { T.revealed = true; foil.style.opacity = 0; }
    const b = $('banner');
    const s = T.strings;
    if (r.win) {
      document.querySelectorAll('.cell').forEach((c) => {
        if (c.dataset.plate === r.plate) c.classList.add('match', ...(JACKPOT_SYMBOLS.has(r.plate) ? ['jackpot'] : []));
      });
      const big = r.kind === 'jackpot' ? s.jackpot : r.kind === 'moonshine' ? s.bigWin : s.win;
      b.className = 'banner ' + (JACKPOT_SYMBOLS.has(r.plate) ? 'jackpot' : 'win');
      b.innerHTML = `${esc(big)}<small>${esc(r.label || LABELS[r.plate] || '')} &middot; ${money(r.payout)}</small>`;
      play('snd-win');
      // Oil Pump progressive jackpot: whoop right after the cha-ching settles
      if (r.kind === 'jackpot') setTimeout(() => play('snd-yeehaw'), 650);
    } else {
      b.className = 'banner lose';
      b.innerHTML = esc(s.lose);
      play(T.loseSound === 'fart' ? 'snd-fart' : 'snd-sadtrombone');
    }
    if (r.pot !== undefined) { $('t-pot').textContent = money(r.pot); if (T.legend) { T.legend.pot = r.pot; renderLegend(T.legend, T.serial); } }
    $('btn-close').disabled = false;
  }

  function openTicket(d) {
    T.serial = d.serial; T.grid = d.grid || []; T.revealed = false; T.claimed = false; T.result = null; T.moves = 0;
    T.strings = d.strings || {};
    T.loseSound = d.loseSound || 'sadtrombone';
    T.legend = d.legend || null;
    const s = T.strings;
    $('t-title').textContent = s.title || 'Deliverance Fortune';
    $('t-subtitle').textContent = s.subtitle || '';
    $('t-year').textContent = s.year || 'Anno 1899';
    $('t-price').textContent = `${money(d.price)} Ticket`;
    $('t-serial').textContent = `${s.serial || 'No.'} ${d.serial}`;
    $('t-pot-label').textContent = s.potLabel || 'Progressive pot';
    $('t-pot').textContent = money(d.pot);
    $('t-prize-key').textContent = s.prizeKey || 'Prize schedule';
    $('t-rules').textContent = s.rules || '';
    $('t-flavour').textContent = s.flavour || '';
    $('btn-reveal').textContent = s.revealAll || 'Reveal all';
    $('btn-flip').textContent = s.flip || 'Flip for odds';
    $('btn-flipback').textContent = s.flipBack || 'Flip back';
    flip(false);
    renderLegend(d.legend, d.serial);
    $('btn-close').textContent = s.close || 'Close';
    $('grid').innerHTML = T.grid.map((p) => `<div class="cell" data-plate="${esc(p)}">${sym(p)}<span class="lbl">${esc(LABELS[p] || p)}</span></div>`).join('');
    $('prize-list').innerHTML = (d.prizes || []).map((p) => `
      <li class="${p.jackpot ? 'jp' : ''} ${p.progressive ? 'prog' : ''}">
        <span>${sym(p.plate)}${sym(p.plate)}${sym(p.plate)}</span>
        <span class="amt">${p.progressive ? 'POT' : money(p.payout)}</span>
      </li>`).join('');
    $('banner').className = 'banner hidden';
    $('btn-reveal').disabled = false; $('btn-close').disabled = true;
    $('ticket-wrap').classList.remove('hidden');
    foil.style.transition = 'none';
    requestAnimationFrame(paintFoil);
  }

  function closeTicket() {
    if ($('btn-close').disabled) return;
    $('ticket-wrap').classList.add('hidden');
    post('closeTicket');
  }
  // ---- back of the ticket: odds legend from the live server config ----
  function renderLegend(lg, serial) {
    if (!lg) return;
    const s = T.strings || {};
    $('b-title').textContent = s.backTitle || 'Odds & Conditions';
    $('b-match').textContent = s.match3 || 'Match 3 to win';
    $('b-price').textContent = `Ticket ${money(lg.price)}`;
    $('b-serial').textContent = `${s.serial || 'No.'} ${serial}`;
    const odds = (n) => '1 in ' + (n >= 100 ? Math.round(n).toLocaleString('en-US') : n.toFixed(2).replace(/\.?0+$/, ''));
    $('b-rows').innerHTML = lg.rows.map((r) => {
      const prize = r.type === 'progressive' ? money(lg.pot) : money(r.payout);
      const note = r.type === 'progressive' ? '<small>progressive jackpot, current pot</small>'
        : r.type === 'price_ratio' ? `<small>${r.ratio === 0.5 ? 'half' : Math.round(r.ratio * 100) + '% of'} your ticket back</small>` : '';
      return `<tr class="${JACKPOT_SYMBOLS.has(r.plate) ? 'jp' : ''}"><td class="ic">${sym(r.plate)}${sym(r.plate)}${sym(r.plate)}</td>
        <td class="nm">${esc(r.label)} ${note}</td><td class="amt">${prize}</td><td class="odds">${odds(r.oddsN)}</td></tr>`;
    }).join('');
    $('b-overall').innerHTML = `<span>Win <b>${pct(lg.winPct)}</b></span><span>Lose <b>${pct(lg.losePct)}</b></span>`;
    $('b-rtp').textContent = `Instant prizes return ${lg.rtpInstant.toFixed(1)}%; including the jackpot, players get back about ${lg.rtpLongRun.toFixed(1)}% over the long run.`
      + (lg.autoScaled ? ' Prizes shown are scaled by the Commission.' : '');
    const feed = [];
    if (lg.lossContributionPct > 0) feed.push(`${lg.lossContributionPct}% of each losing ticket's price`);
    if (lg.jackpotPercent > 0) feed.push(`${lg.jackpotPercent}% of every ticket`);
    $('b-fine').textContent = `The Oil Pump jackpot is fed by ${feed.join(' and ') || 'the Commission seed'}; it reseeds at ${money(lg.seed)} after each win. Odds are per ticket, drawn by the Commission at sale.`;
  }
  const flip = (on) => $('ticket').classList.toggle('flipped', on);
  $('btn-flip').addEventListener('click', () => flip(true));
  $('btn-flipback').addEventListener('click', () => flip(false));

  $('btn-reveal').addEventListener('click', revealAll);
  $('btn-close').addEventListener('click', closeTicket);

  /* ======================= Commission (admin) ledger ======================= */
  const A = { data: null, plates: [], tiers: [] };

  // Mirrors Economy.analyse in server/economy.lua
  // Base price the fixed payouts and seed are written for (Config.basePrice, sent by the server)
  let BASE_PRICE = 10;
  const priceFactor = (s) => s.ticketPrice / (BASE_PRICE || s.ticketPrice);
  function analyse(s, pot) {
    const price = s.ticketPrice, run = s.printRun;
    const f = priceFactor(s), seed = s.jackpot.seed * f;
    let fixedEV = 0, ratioEV = 0, winW = 0, progW = 0;
    for (const t of s.tiers) {
      winW += t.weight;
      if (t.type === 'fixed') fixedEV += t.payout * f * t.weight / run;
      else if (t.type === 'price_ratio') ratioEV += t.ratio * price * t.weight / run;
      else progW += t.weight;
    }
    const losePct = (run - winW) / run * 100;
    const potFeedPct = s.jackpotPercent + losePct / 100 * (s.jackpot.lossContributionPct || 0);
    const seedPct = progW / run * seed / price * 100; // seed re-injected per Oil Pump hit
    const backingPct = 100 - s.houseEdge - potFeedPct - seedPct;
    const target = Math.max(0, price * backingPct / 100 - ratioEV); // only 'fixed' tiers scale
    const scale = s.autoScalePayouts && fixedEV > 0 ? target / fixedEV : 1;
    const basis = s.rtpJackpotBasis === 'seed' ? seed : Math.max(pot || 0, seed);
    const rtpFixed = (fixedEV * scale + ratioEV) / price * 100;
    const rtpProg = progW / run * basis / price * 100;
    const rtpTotal = rtpFixed + rtpProg;
    const rtpLongRun = rtpFixed + potFeedPct + seedPct;
    return {
      backingPct, potFeedPct, scale, rtpFixed, rtpProgressive: rtpProg, rtpTotal, rtpLongRun,
      effectiveEdge: 100 - rtpTotal, longRunEdge: 100 - rtpLongRun,
      winOdds: winW > 0 ? run / winW : 0, winW, winPct: winW / run * 100, losePct,
      edgeAchieved: rtpLongRun <= 100 - s.houseEdge + 1e-6,
      over100: rtpTotal > 100 || rtpLongRun > 100,
    };
  }

  const num = (id) => parseFloat($(id).value);
  function collect() {
    return {
      salesEnabled: $('a-sales').checked, loseSound: $('a-losesound').value,
      ticketPrice: num('a-price'), printRun: Math.floor(num('a-printrun')),
      houseEdge: num('a-edge'), jackpotPercent: num('a-jp'),
      autoScalePayouts: $('a-autoscale').checked, rtpJackpotBasis: $('a-basis').value,
      tiers: A.tiers.map((t) => ({ plate: t.plate, type: t.type, payout: Number(t.payout) || 0, ratio: Number(t.ratio) || 0, weight: Math.floor(Number(t.weight) || 0) })),
      jackpot: {
        seed: num('a-seed'), lossContributionPct: Math.round(num('a-losspct') || 0), maxPot: num('a-maxpot') || 0, drawEnabled: $('a-draw').checked, drawMode: $('a-mode').value,
        intervalHours: num('a-hours'), schedule: $('a-sched').value.split(/[,\s]+/).filter(Boolean),
        minPlayers: Math.floor(num('a-minp')), minTickets: Math.floor(num('a-mint')),
      },
    };
  }

  // What a tier actually pays at the price currently typed in (before saving)
  function paysNow(t) {
    const s = collect();
    if (!(s.ticketPrice > 0) || !(s.printRun > 0)) return '-';
    if (t.type === 'progressive') return 'pot';
    if (t.type === 'price_ratio') return money(s.ticketPrice * (Number(t.ratio) || 0));
    const a = analyse(s, A.data ? A.data.state.pot : 0);
    return money(Math.round((Number(t.payout) || 0) * priceFactor(s) * a.scale * 100) / 100);
  }
  function refreshPays() {
    document.querySelectorAll('#a-tiers tr').forEach((tr) => { const c = tr.querySelector('td.pays'); if (c) c.textContent = paysNow(A.tiers[+tr.dataset.i]); });
  }
  function renderTiers() {
    const run = num('a-printrun') || 1;
    $('a-tiers').innerHTML = A.tiers.map((t, i) => `
      <tr data-i="${i}">
        <td class="sym">${sym(t.plate)}<select data-f="plate">${A.plates.map((p) => `<option value="${p.id}" ${p.id === t.plate ? 'selected' : ''}>${esc(p.label)}</option>`).join('')}</select></td>
        <td><select data-f="type"><option value="fixed" ${t.type === 'fixed' ? 'selected' : ''}>Fixed</option><option value="price_ratio" ${t.type === 'price_ratio' ? 'selected' : ''}>&times;Price</option><option value="progressive" ${t.type === 'progressive' ? 'selected' : ''}>Pot</option></select></td>
        <td>${t.type === 'price_ratio'
          ? `<input type="number" step="0.05" data-f="ratio" value="${t.ratio ?? 0.5}" title="Multiple of ticket price">`
          : `<input type="number" step="1" data-f="payout" value="${t.type === 'progressive' ? '' : t.payout}" ${t.type === 'progressive' ? 'disabled placeholder="pot"' : ''}>`}</td>
        <td><input type="number" step="1" data-f="weight" value="${t.weight}"></td>
        <td class="odds pays">${paysNow(t)}</td>
        <td class="odds">${t.weight > 0 ? '1 in ' + Math.round(run / t.weight).toLocaleString() : '-'}</td>
        <td><button class="rm" title="Strike out">&times;</button></td>
      </tr>`).join('');
  }

  $('a-tiers').addEventListener('change', (e) => {
    const tr = e.target.closest('tr'); if (!tr) return;
    const t = A.tiers[+tr.dataset.i], f = e.target.dataset.f;
    t[f] = f === 'payout' || f === 'weight' || f === 'ratio' ? Number(e.target.value) : e.target.value;
    if (f === 'type' && t.type === 'price_ratio' && !(t.ratio > 0)) t.ratio = 0.5;
    renderTiers(); recompute();
  });
  $('a-tiers').addEventListener('input', (e) => {
    const tr = e.target.closest('tr'); if (!tr || !e.target.dataset.f) return;
    const f = e.target.dataset.f;
    if (f === 'payout' || f === 'weight' || f === 'ratio') { A.tiers[+tr.dataset.i][f] = Number(e.target.value); recompute(); }
  });
  $('a-tiers').addEventListener('click', (e) => {
    if (!e.target.classList.contains('rm')) return;
    A.tiers.splice(+e.target.closest('tr').dataset.i, 1); renderTiers(); recompute();
  });
  $('a-addtier').addEventListener('click', () => {
    const used = new Set(A.tiers.map((t) => t.plate));
    const free = A.plates.find((p) => !used.has(p.id));
    if (!free) { setMsg('Every symbol already has a tier.', 'error'); return; }
    A.tiers.push({ plate: free.id, type: 'fixed', payout: 1, weight: 0 }); renderTiers(); recompute();
  });

  function recompute() {
    const s = collect();
    const errs = [];
    if (!(s.ticketPrice > 0)) errs.push('price');
    if (s.houseEdge + s.jackpotPercent > 100) errs.push('edge + pot % exceed 100');
    if (!(s.jackpot.lossContributionPct >= 0 && s.jackpot.lossContributionPct <= 100)) errs.push('loss-to-jackpot must be 0-100');
    const sum = s.tiers.reduce((a, t) => a + t.weight, 0);
    if (sum > s.printRun) errs.push('tier weights exceed the print run');
    const plates = s.tiers.map((t) => t.plate);
    if (new Set(plates).size !== plates.length) errs.push('a symbol is used twice');
    if (s.tiers.filter((t) => t.type === 'progressive').length > 1) errs.push('only one Pot tier allowed');
    
    $('r-interval').classList.toggle('hidden', s.jackpot.drawMode !== 'interval');
    $('r-schedule').classList.toggle('hidden', s.jackpot.drawMode !== 'schedule');
    if (!(s.printRun > 0) || !(s.ticketPrice > 0) || !s.jackpot) return;
    const a = analyse(s, A.data ? A.data.state.pot : 0);
    $('a-backing').textContent = pct(a.backingPct);
    refreshPays();
    $('a-seednow').textContent = money(s.jackpot.seed * priceFactor(s));
    $('r-feed').textContent = pct(a.potFeedPct);
    $('r-ledge').textContent = pct(a.longRunEdge);
    $('r-total').textContent = pct(a.rtpTotal);
    $('r-fixed').textContent = pct(a.rtpFixed);
    $('r-prog').textContent = pct(a.rtpProgressive) + (s.rtpJackpotBasis === 'seed' ? ' (seed)' : ' (pot)');
    $('r-long').textContent = pct(a.rtpLongRun);
    $('r-edge').textContent = pct(a.effectiveEdge);
    $('r-winlose').textContent = `${pct(a.winPct)} / ${pct(a.losePct)}`;
    $('r-odds').textContent = a.winOdds ? '1 in ' + a.winOdds.toFixed(2) : '-';
    $('r-scale').textContent = s.autoScalePayouts ? '\u00d7' + a.scale.toFixed(3) : 'off';
    const warns = [...errs.map((e) => 'Invalid: ' + e)];
    if (a.over100) warns.push('Return to player exceeds 100% - the lottery would ADD money to the economy.');
    else if (!a.edgeAchieved) warns.push(`Configured house edge of ${pct(s.houseEdge)} is not achieved in the long run (prizes + pot feed). Lower payouts/weights or the pot feed.`);
    $('r-warn').classList.toggle('hidden', !warns.length);
    $('r-warn').innerHTML = warns.map(esc).join('<br>');
    $('rtp-box').classList.toggle('over', a.over100 || !a.edgeAchieved);
    $('a-save').disabled = errs.length > 0;
  }
  ['a-sales', 'a-price', 'a-printrun', 'a-edge', 'a-jp', 'a-autoscale', 'a-basis', 'a-seed', 'a-losspct', 'a-maxpot', 'a-draw', 'a-mode', 'a-hours', 'a-sched', 'a-minp', 'a-mint']
    .forEach((id) => $(id).addEventListener('input', () => { if (id === 'a-printrun') renderTiers(); recompute(); }));

  const fmtTime = (t) => (t ? new Date(t * 1000).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : '-');
  function setMsg(text, kind) { $('a-msg').textContent = text || ''; $('a-msg').className = 'msg ' + (kind || ''); }

  function renderAdmin(d) {
    A.data = d; A.plates = d.plates || [];
    if (d.basePrice > 0) { BASE_PRICE = d.basePrice; $('a-baseprice').textContent = money(d.basePrice); }
    const s = d.settings;
    A.tiers = s.tiers.map((t) => ({ ...t }));
    $('a-sales').checked = !!s.salesEnabled; $('a-losesound').value = s.loseSound || 'sadtrombone'; $('a-price').value = s.ticketPrice; $('a-printrun').value = s.printRun;
    $('a-edge').value = s.houseEdge; $('a-jp').value = s.jackpotPercent; $('a-autoscale').checked = !!s.autoScalePayouts;
    $('a-basis').value = s.rtpJackpotBasis || 'current';
    const j = s.jackpot;
    $('a-seed').value = j.seed; $('a-losspct').value = j.lossContributionPct ?? 0; $('a-maxpot').value = j.maxPot || 0; $('a-draw').checked = !!j.drawEnabled; $('a-mode').value = j.drawMode;
    $('a-hours').value = j.intervalHours; $('a-sched').value = (Array.isArray(j.schedule) ? j.schedule : []).join(', ');
    $('a-minp').value = j.minPlayers; $('a-mint').value = j.minTickets;
    renderTiers();

    const st = d.state, l = d.ledger;
    $('l-pot').textContent = money(st.pot);
    $('l-entries').textContent = `${st.entries} tickets / ${st.entrants} entrants`;
    $('l-last').textContent = fmtTime(st.lastDraw);
    $('l-next').textContent = j.drawEnabled ? fmtTime(st.nextDraw) : 'draws disabled';
    $('l-sold').textContent = Number(l.sold).toLocaleString();
    $('l-in').textContent = money(l.moneyIn);
    $('l-instant').textContent = money(l.instantPaid);
    $('l-jpaid').textContent = money(l.jackpotPaid);
    $('l-house').textContent = money(l.houseRetained);
    $('l-seeds').textContent = money(l.seedsInjected);
    $('l-net').textContent = money(l.netRemoved);
    $('l-rtp').textContent = pct(l.actualRtp);
    const kindLabel = { instant: '', moonshine: '', jackpot: 'Pot', draw: 'Draw' };
    $('l-winners').innerHTML = (d.winners || []).map((w) => `
      <tr class="${w.kind === 'jackpot' || w.kind === 'draw' || w.kind === 'moonshine' ? 'jp' : ''}">
        <td>${esc(w.created_at)}</td><td>${esc(w.name)}</td>
        <td>${esc(w.plate ? (LABELS[w.plate] || w.plate) : '')} ${esc(kindLabel[w.kind] || '')}</td><td>${money(w.amount)}</td></tr>`).join('')
      || '<tr><td colspan="4"><i>No entries yet.</i></td></tr>';
    $('a-meta').textContent = `Framework: ${d.framework} \u00b7 Persistence: ${d.persistence} \u00b7 Draw period #${st.period}`;
    setMsg(d.message, d.messageKind);
    recompute();
  }

  $('a-save').addEventListener('click', () => { setMsg('Sending figures to the Commission...', ''); post('adminSave', collect()); if (MOCK) setMsg('The Commission ledger has been amended.', 'ok'); });
  $('a-refresh').addEventListener('click', () => post('adminRefresh'));
  $('a-drawnow').addEventListener('click', () => post('adminDrawNow', { ignoreMin: $('a-ignoremin').checked }));
  $('a-defaults').addEventListener('click', () => { if (A.data && A.data.defaults) { const d = { ...A.data, settings: A.data.defaults, message: 'Defaults loaded - press "Enter in ledger" to keep them.' }; renderAdmin(d); } });
  $('a-close').addEventListener('click', () => { $('admin-wrap').classList.add('hidden'); post('closeAdmin'); });

  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (!$('admin-wrap').classList.contains('hidden')) $('a-close').click();
    else if (!$('ticket-wrap').classList.contains('hidden')) closeTicket();
  });

  /* ======================= Message bus ======================= */
  window.addEventListener('message', (e) => {
    const m = e.data || {};
    switch (m.action) {
      case 'openTicket': openTicket(m.data); break;
      case 'result': showResult(m.data); break;
      case 'toast': toast(m.data); break;
      case 'telegram': telegram(m.data); break;
      case 'openAdmin': $('admin-wrap').classList.remove('hidden'); setMsg('Fetching the ledger...', ''); break;
      case 'adminData': renderAdmin(m.data); break;
      default: break;
    }
  });

  /* ======================= Mock mode (browser preview) ======================= */
  const MOCK_STRINGS = {
    title: 'Deliverance Fortune', subtitle: 'Territorial Lottery of the State of Deliverance', year: 'Anno 1899',
    rules: 'Scratch all three plates. Match 3 alike to win the sum shown. 3 Silver Dollars return half your stake; 3 Oil Pumps strike the Progressive Jackpot.',
    flavour: 'Licensed by the Commission. Void where Providence forbids. Not redeemable for land, livestock, or spouses.',
    scratch: 'SCRATCH HERE', revealAll: 'Reveal all', close: 'Fold & pocket', win: 'A WINNER!', lose: 'NOT A WINNER',
    jackpot: 'PROGRESSIVE JACKPOT!', bigWin: 'MOONSHINE FORTUNE!', potLabel: 'Progressive pot', serial: 'No.', prizeKey: 'Prize schedule',
    waiting: 'The clerk is checking your ticket...',
  };
  const DEFAULT_TIERS = [
    { plate: 'SILVER_DOLLAR', type: 'price_ratio', ratio: 0.5, payout: 0, weight: 28886 },
    { plate: 'HORSESHOES', type: 'fixed', payout: 1, weight: 8000 },
    { plate: 'COWBOY_HAT', type: 'fixed', payout: 5, weight: 10000 },
    { plate: 'TOP_HAT', type: 'fixed', payout: 10, weight: 14000 },
    { plate: 'GOLD_NUGGET', type: 'fixed', payout: 100, weight: 300 },
    { plate: 'MOONSHINE', type: 'fixed', payout: 1000, weight: 12 },
    { plate: 'OIL_PUMP', type: 'progressive', payout: 0, weight: 2 },
  ];
  // Mock legend computed the same way as Economy.legend() (defaults, auto-scale off)
  function mockLegend(pot) {
    const s = { ticketPrice: 10, printRun: 120000, houseEdge: 30, jackpotPercent: 0, autoScalePayouts: false, rtpJackpotBasis: 'seed',
      tiers: DEFAULT_TIERS, jackpot: { seed: 2500, lossContributionPct: 50 } };
    const a = analyse(s, pot);
    const rows = DEFAULT_TIERS.map((t) => ({ plate: t.plate, label: LABELS[t.plate], type: t.type, ratio: t.ratio,
      payout: t.type === 'price_ratio' ? 10 * t.ratio : t.type === 'progressive' ? pot : t.payout, oddsN: 120000 / t.weight }));
    const rank = { progressive: 0, fixed: 1, price_ratio: 2 };
    rows.sort((x, y) => (rank[x.type] - rank[y.type]) || (y.payout - x.payout));
    return { price: 10, rows, pot, seed: 2500, winPct: a.winPct, losePct: a.losePct, rtpInstant: a.rtpFixed, rtpLongRun: a.rtpLongRun,
      lossContributionPct: 50, jackpotPercent: 0, autoScaled: false };
  }
  function mockResult() {
    const counts = {};
    T.grid.forEach((p) => { counts[p] = (counts[p] || 0) + 1; });
    const plate = Object.keys(counts).find((p) => counts[p] >= 3 && p !== 'TUMBLEWEED');
    const tier = DEFAULT_TIERS.find((t) => t.plate === plate);
    if (!tier) return { win: false, kind: 'loss', pot: 3187 };
    return { win: true, plate, label: LABELS[plate], payout: tier.type === 'progressive' ? 3187 : tier.type === 'price_ratio' ? 10 * tier.ratio : tier.payout,
      kind: plate === 'OIL_PUMP' ? 'jackpot' : plate === 'MOONSHINE' ? 'moonshine' : 'instant', pot: 2500 };
  }

  if (MOCK) {
    document.body.classList.add('mock');
    if (MOCK !== 'admin') document.body.classList.add('scene');
    if (MOCK === 'ticket' || MOCK === 'telegram') {
      const win = params.get('win') || 'OIL_PUMP';
      const grids = {
        OIL_PUMP: ['OIL_PUMP', 'OIL_PUMP', 'OIL_PUMP'],
        MOONSHINE: ['MOONSHINE', 'MOONSHINE', 'MOONSHINE'],
        SILVER_DOLLAR: ['SILVER_DOLLAR', 'SILVER_DOLLAR', 'SILVER_DOLLAR'],
        TOP_HAT: ['TOP_HAT', 'TOP_HAT', 'TOP_HAT'],
        loss: ['OIL_PUMP', 'TUMBLEWEED', 'OIL_PUMP'],
      };
      openTicket({
        serial: '004217', grid: grids[win] || grids.OIL_PUMP, pot: 3187, price: 10, strings: MOCK_STRINGS, legend: mockLegend(3187),
        prizes: DEFAULT_TIERS.map((t) => ({ plate: t.plate, payout: t.type === 'price_ratio' ? 10 * t.ratio : t.payout, progressive: t.type === 'progressive', jackpot: JACKPOT_SYMBOLS.has(t.plate) })),
      });
      // simulate a partial scratch so screenshots show foil + revealed plates
      const stage = params.get('stage') || 'partial';
      if (params.get('back')) { document.querySelector('.flip').style.transition = 'none'; flip(true); } // instant flip for screenshots
      setTimeout(() => {
        if (stage === 'full') { revealAll(); return; }
        if (stage === 'partial') {
          // scratch the first plate and half of the second
          const w = foil.width, h = foil.height;
          for (let a = 0; a < 60; a++) scratchAt(w / 6 + Math.sin(a * 0.8) * 34, 10 + a * 1.9);
          for (let a = 0; a < 30; a++) scratchAt(w / 2 - 20 + Math.sin(a * 0.8) * 22, 10 + a * 2.2);
        }
      }, 120);
      if (MOCK === 'telegram') telegram({ head: 'WESTERN TERRITORIAL TELEGRAPH CO.', body: 'Ada Whitlock of this Territory scratched three Oil Pumps and claims the Progressive Jackpot of $3,187. STOP. Pot reseeded at $2,500. STOP.', sign: 'By order of the State of Deliverance Lottery Commission' });
    }
    if (MOCK === 'admin') {
      $('admin-wrap').classList.remove('hidden');
      const defaults = {
        salesEnabled: true, loseSound: 'sadtrombone', ticketPrice: 10, printRun: 120000, houseEdge: 30, jackpotPercent: 0, autoScalePayouts: false, rtpJackpotBasis: 'current',
        tiers: DEFAULT_TIERS, jackpot: { seed: 2500, lossContributionPct: 50, maxPot: 0, drawEnabled: true, drawMode: 'interval', intervalHours: 24, schedule: ['20:00'], minPlayers: 3, minTickets: 10 },
      };
      const now = Math.floor(Date.now() / 1000);
      renderAdmin({
        settings: defaults, defaults, basePrice: 10, framework: 'vorp', persistence: 'oxmysql',
        plates: Object.keys(LABELS).filter((k) => k !== 'TUMBLEWEED').map((id) => ({ id, label: LABELS[id], jackpot: JACKPOT_SYMBOLS.has(id) })),
        state: { pot: 3187, period: 4, lastDraw: now - 6 * 3600, nextDraw: now + 18 * 3600, entries: 687, entrants: 41 },
        ledger: { sold: 6870, moneyIn: 68700, instantPaid: 13712, jackpotPaid: 7400, houseRetained: 20610, seedsInjected: 10000, netRemoved: 47588, actualRtp: 30.73 },
        winners: [
          { created_at: '1899-06-14 21:02', name: 'Ada Whitlock', plate: null, kind: 'draw', amount: 2950 },
          { created_at: '1899-06-14 19:44', name: 'Jeb Calloway', plate: 'GOLD_NUGGET', kind: 'instant', amount: 100 },
          { created_at: '1899-06-14 18:10', name: 'Silas Merriweather', plate: 'MOONSHINE', kind: 'moonshine', amount: 1000 },
          { created_at: '1899-06-14 17:31', name: 'Hattie Brennan', plate: 'TOP_HAT', kind: 'instant', amount: 10 },
          { created_at: '1899-06-13 22:58', name: 'Eli Ransome', plate: 'OIL_PUMP', kind: 'jackpot', amount: 4450 },
          { created_at: '1899-06-13 20:15', name: 'Clara Dunmore', plate: 'COWBOY_HAT', kind: 'instant', amount: 5 },
        ],
      });
    }
  }
})();
