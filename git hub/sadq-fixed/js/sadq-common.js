// ════════════════════════════════════════════════════════════════════
// SADQ — sadq-common.js
// Shared utilities: toast, modal, sidebar, confirm dialog
// Loaded as a regular (non-module) script on pages that need UI helpers
// ════════════════════════════════════════════════════════════════════

// ── TOAST SYSTEM ────────────────────────────────────────────────────
function showToast(message, type, duration) {
  type = type || 'info';
  duration = duration || 3500;
  var container = document.querySelector('.toast-container');
  if (!container) {
    container = document.createElement('div');
    container.className = 'toast-container';
    document.body.appendChild(container);
  }
  var toast = document.createElement('div');
  toast.className = 'toast toast--' + type;
  toast.textContent = message;
  container.appendChild(toast);
  setTimeout(function() {
    toast.classList.add('removing');
    setTimeout(function() { toast.remove(); }, 300);
  }, duration);
}
window.showToast = showToast;

// ── MODAL SYSTEM ────────────────────────────────────────────────────
function openModal(id) {
  var m = document.getElementById(id);
  if (m) {
    m.classList.add('show');
    document.body.style.overflow = 'hidden';
    var firstInput = m.querySelector('input, select, textarea');
    if (firstInput) firstInput.focus();
  }
}
window.openModal = openModal;

function closeModal(id) {
  var m = document.getElementById(id);
  if (m) {
    m.classList.remove('show');
    document.body.style.overflow = '';
  }
}
window.closeModal = closeModal;

// Close modal on background click
document.addEventListener('click', function(e) {
  if (e.target && e.target.classList && e.target.classList.contains('modal-overlay')) {
    e.target.classList.remove('show');
    document.body.style.overflow = '';
  }
});

// ── SIDEBAR CONTROLS ─────────────────────────────────────────────────
function closeSidebar() {
  var sb = document.getElementById('sidebar');
  var ov = document.getElementById('sidebar-overlay');
  if (sb) sb.classList.remove('sidebar--open');
  if (ov) ov.classList.remove('show');
}
window.closeSidebar = closeSidebar;

function openSidebar() {
  var sb = document.getElementById('sidebar');
  var ov = document.getElementById('sidebar-overlay');
  if (sb) sb.classList.add('sidebar--open');
  if (ov) ov.classList.add('show');
}
window.openSidebar = openSidebar;

// ── ESC KEY — close modals + sidebar ─────────────────────────────────
document.addEventListener('keydown', function(e) {
  if (e.key === 'Escape') {
    document.querySelectorAll('.modal-overlay.show').forEach(function(m) {
      m.classList.remove('show');
      document.body.style.overflow = '';
    });
    closeSidebar();
  }
});

// ── MENU TOGGLE — wire up on DOMContentLoaded ───────────────────────
document.addEventListener('DOMContentLoaded', function() {
  var toggle = document.getElementById('menu-toggle');
  if (toggle) {
    toggle.addEventListener('click', function() {
      var sb = document.getElementById('sidebar');
      if (sb && sb.classList.contains('sidebar--open')) {
        closeSidebar();
      } else {
        openSidebar();
      }
    });
  }

  // Close sidebar on link click (mobile)
  document.querySelectorAll('.sidebar__link').forEach(function(link) {
    link.addEventListener('click', function() {
      if (window.innerWidth <= 768) closeSidebar();
    });
  });

  // Wire up logout button
  var logoutBtn = document.getElementById('logout-btn');
  if (logoutBtn) {
    logoutBtn.addEventListener('click', function(e) {
      e.preventDefault();
      localStorage.removeItem('teacher_session');
      localStorage.removeItem('subwing_session');
      // Try Supabase signOut if available
      if (window.__supabase) {
        window.__supabase.auth.signOut().then(function() {
          window.location.href = '/login.html';
        });
      } else {
        window.location.href = '/login.html';
      }
    });
  }
});

// ── CUSTOM CONFIRM DIALOG ────────────────────────────────────────────
window.sadqConfirm = function(msg) {
  return new Promise(function(resolve) {
    var d = document.createElement('div');
    d.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.6);backdrop-filter:blur(4px);z-index:9999;display:flex;align-items:center;justify-content:center;padding:16px';
    d.innerHTML = '<div style="background:#10152A;color:#F8FAFC;border-radius:14px;padding:28px;max-width:360px;width:100%;box-shadow:0 20px 60px rgba(0,0,0,0.4);border:1px solid rgba(255,255,255,0.08)"><p style="font-size:0.95rem;margin-bottom:20px">' + msg + '</p><div style="display:flex;gap:10px;justify-content:flex-end"><button id="cf-no" style="padding:8px 18px;border:1px solid rgba(255,255,255,0.15);background:transparent;color:#94A3B8;border-radius:8px;cursor:pointer;font-family:inherit;font-size:0.875rem">Cancel</button><button id="cf-yes" style="padding:8px 18px;background:#EF4444;color:#fff;border:none;border-radius:8px;cursor:pointer;font-family:inherit;font-weight:600;font-size:0.875rem">Confirm</button></div></div>';
    document.body.appendChild(d);
    document.body.style.overflow = 'hidden';
    var cleanup = function() { d.remove(); document.body.style.overflow = ''; };
    d.querySelector('#cf-yes').onclick = function() { cleanup(); resolve(true); };
    d.querySelector('#cf-no').onclick = function() { cleanup(); resolve(false); };
    d.onclick = function(e) { if (e.target === d) { cleanup(); resolve(false); } };
    d.querySelector('#cf-yes').focus();
  });
};

// ── SCROLL PROGRESS (throttled via rAF) ──────────────────────────────
var scrollTicking = false;
window.addEventListener('scroll', function() {
  if (!scrollTicking) {
    requestAnimationFrame(function() {
      var prog = document.getElementById('scroll-prog');
      if (prog) {
        var sc = (window.scrollY / (document.body.scrollHeight - window.innerHeight)) * 100;
        prog.style.width = sc + '%';
      }
      var nav = document.getElementById('navbar');
      if (nav) nav.classList.toggle('scrolled', window.scrollY > 40);
      scrollTicking = false;
    });
    scrollTicking = true;
  }
});

// ── REVEAL ON SCROLL (IntersectionObserver) ─────────────────────────
if ('IntersectionObserver' in window) {
  var revealObs = new IntersectionObserver(function(entries) {
    entries.forEach(function(e) {
      if (e.isIntersecting) {
        e.target.classList.add('visible');
        revealObs.unobserve(e.target);
      }
    });
  }, { threshold: 0.15, rootMargin: '0px 0px -50px 0px' });
  document.querySelectorAll('.reveal, .stagger').forEach(function(el) { revealObs.observe(el); });
}

// ── GLOBAL ERROR HANDLER ─────────────────────────────────────────────
window.addEventListener('error', function(e) {
  console.error('[SADQ Error]', e.error || e.message);
});
window.addEventListener('unhandledrejection', function(e) {
  console.error('[SADQ Rejection]', e.reason);
  e.preventDefault();
});
