// ═══════════════════════════════════════════════════════════════
// SADQ — SMOOTH SCROLL + SCROLL REVEAL SYSTEM
// Uses Intersection Observer (lightweight, no dependencies)
// ═══════════════════════════════════════════════════════════════

// ── Scroll Progress Bar ──
function initScrollProgress() {
  const bar = document.createElement('div');
  bar.className = 'scroll-progress';
  document.body.appendChild(bar);
  window.addEventListener('scroll', () => {
    const scrolled = (window.scrollY / (document.documentElement.scrollHeight - window.innerHeight)) * 100;
    bar.style.width = Math.min(scrolled, 100) + '%';
  }, { passive: true });
}

// ── Navbar Scroll Effect ──
function initNavbarScroll() {
  const navbar = document.querySelector('.navbar');
  if (!navbar) return;
  const onScroll = () => {
    if (window.scrollY > 50) navbar.classList.add('scrolled');
    else navbar.classList.remove('scrolled');
  };
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();
}

// ── Scroll Reveal (Intersection Observer) ──
function initScrollReveal() {
  const elements = document.querySelectorAll(
    '.reveal-up, .reveal-down, .reveal-left, .reveal-right, .reveal-scale, .reveal-fade, .stagger-group'
  );
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('active');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.1, rootMargin: '0px 0px -50px 0px' });

  elements.forEach(el => observer.observe(el));
}

// ── Counter Animation ──
function initCounters() {
  const counters = document.querySelectorAll('[data-counter]');
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return;
      const el = entry.target;
      const target = parseInt(el.dataset.counter);
      const duration = 1500;
      const start = performance.now();
      const animate = (now) => {
        const progress = Math.min((now - start) / duration, 1);
        const eased = 1 - Math.pow(1 - progress, 3);
        el.textContent = Math.floor(eased * target).toLocaleString('en-IN');
        if (progress < 1) requestAnimationFrame(animate);
      };
      requestAnimationFrame(animate);
      observer.unobserve(el);
    });
  }, { threshold: 0.5 });
  counters.forEach(c => observer.observe(c));
}

// ── Parallax (lightweight) ──
function initParallax() {
  if (window.matchMedia('(max-width: 600px)').matches) return;
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const elements = document.querySelectorAll('[data-parallax]');
  if (!elements.length) return;
  window.addEventListener('scroll', () => {
    const scrolled = window.scrollY;
    elements.forEach(el => {
      const speed = parseFloat(el.dataset.parallax) || 0.3;
      el.style.transform = `translateY(${scrolled * speed * 0.1}px)`;
    });
  }, { passive: true });
}

// ── Init All ──
function initAll() {
  initScrollProgress();
  initNavbarScroll();
  initScrollReveal();
  initCounters();
  initParallax();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initAll);
} else {
  initAll();
}

// Re-init for dynamic content
window.sadqReinit = initAll;
