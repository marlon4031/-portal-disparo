// Configuração do Supabase. Preencha com os dados do seu projeto:
// Supabase → Project Settings → API (ou "Connect" no topo do painel).
// A chave "anon/public" pode ficar aqui: ela é pública por design e o acesso
// aos dados é controlado pelas regras de segurança (RLS) do schema.sql.
// NUNCA coloque aqui a chave "service_role".
window.PORTAL_CONFIG = {
  SUPABASE_URL: '',        // ex: 'https://abcdefghijkl.supabase.co'
  SUPABASE_ANON_KEY: '',   // ex: 'eyJhbGciOi...'
  EMAIL_DOMAIN: 'disparo.local' // domínio interno dos logins (usuario@disparo.local)
};
