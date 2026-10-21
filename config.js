// Public Supabase settings. The anon/publishable key is safe to ship to browsers:
// what each signed-in person can read or write is enforced by the row-level
// security rules in supabase/schema.sql, not by keeping this key secret.
// Never put the service_role / secret key here.
window.LIFTLOG_CONFIG = {
  supabaseUrl: "https://rdjkwsuhmsxytmkaspjb.supabase.co",
  supabaseAnonKey: "sb_publishable_sPfyhxDOh39KVLj01-VYEQ_3ReWVW5l"
};
