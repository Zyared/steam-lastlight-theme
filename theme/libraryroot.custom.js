// Last Light theme: decorative overlays for the main Steam window. Makes no network requests.
(() => {
  const start = () => {
    const root = document.documentElement;
    if (!root.classList.contains('MillenniumWindow_MainSteamWindow') || document.getElementById('ll-scan')) return;

    const BULB = '<svg viewBox="0 0 24 31"><path fill="currentColor" d="M12 0a11 11 0 0 0-6 20.2V24h12v-3.8A11 11 0 0 0 12 0z"/><rect x="7" y="25" width="10" height="2" fill="currentColor" opacity=".55"/><rect x="8" y="28" width="8" height="2" fill="currentColor" opacity=".55"/></svg>';
    const add = (tag, id, html) => {
      const el = document.createElement(tag);
      el.id = id;
      if (html) el.innerHTML = html;
      document.body.appendChild(el);
      return el;
    };

    add('div', 'll-scan');
    add('div', 'll-logo', `${BULB}<span>LAST LIGHT</span>`);

    // HUD: real clock and session uptime, once a second, skipped while hidden.
    const hud = add('div', 'll-hud', '<u>&#9632;</u><span>LIGHT <b>ON</b></span><span>T <b class="t"></b></span><span>UP <b class="u"></b></span>');
    const clock = hud.querySelector('.t'), uptime = hud.querySelector('.u');
    const began = Date.now();
    const pad = n => String(n).padStart(2, '0');
    const tickHud = () => {
      if (document.hidden) return;
      const d = new Date(), s = Math.floor((Date.now() - began) / 1000);
      clock.textContent = `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
      uptime.textContent = `${pad(Math.floor(s / 3600))}:${pad(Math.floor(s / 60) % 60)}:${pad(s % 60)}`;
    };
    tickHud();
    setInterval(tickHud, 1000);

    const vis = () => root.classList.toggle('ll-hidden', document.hidden);
    document.addEventListener('visibilitychange', vis);
    vis();

    // Start screen: once per client session, never blocks clicks.
    let seen = false;
    try { seen = !!sessionStorage.getItem('ll-boot'); sessionStorage.setItem('ll-boot', '1'); } catch {}
    const playBoot = () => {
      const boot = add('div', 'll-boot', `${BULB}<h1>LAST LIGHT</h1><pre></pre>`);
      const pre = boot.querySelector('pre');
      const text = '> power ........ ok\n> filament ..... warm\n> the dark can wait.';
      // Based on elapsed time, so a throttled timer in an unfocused window cannot leave it unfinished.
      const t0 = Date.now();
      const run = setInterval(() => {
        const ms = Date.now() - t0;
        pre.textContent = text.slice(0, Math.floor(Math.max(0, ms - 900) / 24));
        if (ms >= 2600) clearInterval(run);
      }, 30);
      setTimeout(() => boot.remove(), 3300);
    };
    if (!seen) {
      // Wait for the interface to be on screen, otherwise the sequence plays unseen. Gives up after 30 s.
      const waitFrom = Date.now();
      const wait = setInterval(() => {
        const ready = document.querySelector('.TopBar') && !document.hidden;
        if (ready) playBoot();
        if (ready || Date.now() - waitFrom > 30000) clearInterval(wait);
      }, 100);
    }
  };
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();