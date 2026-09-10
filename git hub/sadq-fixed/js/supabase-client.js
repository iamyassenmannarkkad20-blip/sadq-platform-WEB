// ════════════════════════════════════════════════════════════════════
// SADQ — SUPABASE CLIENT CONFIGURATION
// Central Supabase client — imported by every page that needs DB access
// ════════════════════════════════════════════════════════════════════
//
// SECURITY:
//   • Only the ANON KEY is exposed here — this is safe, it's public.
//   • The SERVICE ROLE KEY is NEVER included in frontend code.
//   • All sensitive operations are protected by PostgreSQL RLS.
//
// USAGE:
//   <script type="module" src="/js/supabase-client.js"></script>
//   import { supabase, getCurrentUser } from '/js/supabase-client.js';
// ════════════════════════════════════════════════════════════════════

import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

// ── Supabase Project Configuration ──────────────────────────────────
const SUPABASE_URL = 'https://fqydxndckhgxeqkgykdl.supabase.co';

// This is the PUBLIC anon key — safe to expose in frontend.
// RLS policies protect all data; this key cannot bypass them.
const SUPABASE_ANON_KEY = 'sb_publishable_KZ_ayfDfmXKsZm_DhH6WgQ_5RYIyzKS';

// ── Create the singleton client ────────────────────────────────────
export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: 'pkce',
  },
  realtime: {
    params: { eventsPerSecond: 2 },
  },
  global: {
    headers: { 'x-client-info': 'sadq-web' },
  },
});

// ── Auth Helpers ────────────────────────────────────────────────────

/**
 * Get the current authenticated user, or null.
 * @returns {Promise<{user: object|null, profile: object|null}>}
 */
export async function getCurrentUser() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { user: null, profile: null };

  const { data: profile, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', user.id)
    .single();

  if (error) {
    console.error('[SADQ] Failed to load profile:', error.message);
    return { user, profile: null };
  }

  return { user, profile };
}

/**
 * Require authentication — redirects to login if not authenticated.
 * Call at the top of protected pages.
 * @returns {Promise<{user: object, profile: object}>}
 */
export async function requireAuth() {
  const { user, profile } = await getCurrentUser();

  if (!user) {
    window.location.href = '/login.html?redirect=' + encodeURIComponent(window.location.pathname);
    throw new Error('Not authenticated');
  }

  if (!profile || profile.account_status !== 'active') {
    const status = profile?.account_status || 'unknown';
    window.location.href = '/login.html?message=' + encodeURIComponent(status);
    throw new Error('Account is not active');
  }

  return { user, profile: profile || {} };
}

/** Verify a teacher's local session against the active database record. */
export async function verifyTeacherSession(teacherId) {
  if (!teacherId) return null;
  const { data, error } = await supabase.rpc('verify_teacher_session', { p_teacher_id: teacherId });
  if (error) throw error;
  const row = Array.isArray(data) ? data[0] : data;
  return row && row.id ? row : null;
}

/** Verify a sub-wing's local session against the active database record. */
export async function verifySubwingSession(subwingId) {
  if (!subwingId) return null;
  const { data, error } = await supabase.rpc('verify_subwing_session', { p_subwing_id: subwingId });
  if (error) throw error;
  const row = Array.isArray(data) ? data[0] : data;
  return row && row.id ? row : null;
}

/**
 * Require a specific role — redirects if user doesn't have it.
 * @param {string[]} roles - e.g. ['admin', 'super_admin']
 * @returns {Promise<{user: object, profile: object}>}
 */
export async function requireRole(roles) {
  const { user, profile } = await requireAuth();

  if (!roles.includes(profile.role)) {
    window.location.href = '/dashboard.html';
    throw new Error('Insufficient permissions');
  }

  return { user, profile };
}

/**
 * Sign out the current user.
 */
export async function signOut() {
  await supabase.auth.signOut();
  window.location.href = '/login.html';
}

// ── Auth State Listener ─────────────────────────────────────────────
// Pages can subscribe to auth state changes

export function onAuthStateChange(callback) {
  return supabase.auth.onAuthStateChange((event, session) => {
    callback(event, session);
  });
}

// ── Default export for non-module scripts ───────────────────────────
export default supabase;


// HTML escape for XSS prevention
export function esc(s){if(!s)return'';return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');}

// Global error handlers
window.addEventListener('error',e=>console.error('[SADQ Error]',e.error||e.message));
window.addEventListener('unhandledrejection',e=>{console.error('[SADQ Rejection]',e.reason);e.preventDefault();});
