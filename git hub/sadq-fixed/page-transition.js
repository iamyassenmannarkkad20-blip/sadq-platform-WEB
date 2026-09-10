// ═══════════════════════════════════════════════════════════════
// SADQ — PAGE TRANSITIONS (FIXED — no flicker on load)
// Purple overlay transition between pages
// ═══════════════════════════════════════════════════════════════

(function() {
  // Create transition overlay — starts hidden, NO transition
  // so the first pageshow doesn't animate anything.
  const overlay = document.createElement('div');
  overlay.id = 'page-transition-overlay';
  overlay.style.cssText = `
    position: fixed; inset: 0; z-index: 9998;
    background: linear-gradient(135deg, #8B5CF6, #3B82F6);
    opacity: 0; pointer-events: none;
    transition: none;
  `;
  document.body.appendChild(overlay);

  // On page load / bfcache restore: force opacity 0 instantly
  // (no transition — prevents the purple flash on every page).
  window.addEventListener('pageshow', () => {
    overlay.style.transition = 'none';
    overlay.style.opacity = '0';
  });

  // Intercept internal link clicks — show overlay THEN navigate.
  // The transition is enabled only here, for the outgoing fade.
  document.addEventListener('click', (e) => {
    const link = e.target.closest('a');
    if (!link) return;
    const href = link.getAttribute('href');
    if (!href || href.startsWith('#') || href.startsWith('http') || href.startsWith('mailto') || link.target === '_blank') return;
    if (e.ctrlKey || e.metaKey) return;

    // Only for internal .html pages
    if (href.endsWith('.html') || href === '/' || href.endsWith('/')) {
      e.preventDefault();
      overlay.style.transition = 'opacity 0.3s ease';
      overlay.style.opacity = '1';
      setTimeout(() => { window.location.href = href; }, 300);
    }
  });
})();
