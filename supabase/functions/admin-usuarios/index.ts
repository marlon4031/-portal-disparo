// Edge Function: admin-usuarios
// Cria, exclui e redefine a senha dos acessos das regionais.
// Só o administrador logado pode chamar. Usa a service role, que nunca vai para o navegador.
//
// Corpo (JSON):
//   { "acao": "criar",   "usuario": "mg70", "senha": "...", "regional": "MG.70", "trocar_senha": true }
//   { "acao": "excluir", "usuario": "mg70" }
//   { "acao": "senha",   "usuario": "mg70", "senha": "...", "trocar_senha": true }
//
// Deploy:  supabase functions deploy admin-usuarios
// Variável opcional: EMAIL_DOMAIN (padrão "disparo.local"), igual à do config.js.

import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const DOMINIO = Deno.env.get("EMAIL_DOMAIN") ?? "disparo.local";
const USUARIO_OK = /^[a-z0-9._-]{2,40}$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ erro: "método não permitido" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // 1) quem está chamando?
  const authHeader = req.headers.get("Authorization") ?? "";
  const caller = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
  const { data: { user }, error: userErr } = await caller.auth.getUser();
  if (userErr || !user) return json({ erro: "não autenticado" }, 401);

  const admin = createClient(url, service, { auth: { persistSession: false } });
  const { data: perfil } = await admin.from("perfis").select("papel").eq("id", user.id).maybeSingle();
  if (perfil?.papel !== "admin") return json({ erro: "apenas o administrador pode gerenciar acessos" }, 403);

  // 2) o que fazer
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ erro: "JSON inválido" }, 400); }
  const acao = String(body.acao ?? "");
  const usuario = String(body.usuario ?? "").trim().toLowerCase();
  if (!USUARIO_OK.test(usuario)) {
    return json({ erro: "usuário inválido: use de 2 a 40 letras minúsculas, números, ponto, hífen ou _" }, 400);
  }
  const email = `${usuario}@${DOMINIO}`;

  if (acao === "criar") {
    const senha = String(body.senha ?? "");
    const regional = String(body.regional ?? "").trim();
    if (senha.length < 6) return json({ erro: "a senha precisa ter ao menos 6 caracteres" }, 400);
    if (!regional) return json({ erro: "informe a regional" }, 400);
    const { data: reg } = await admin.from("regionais").select("nome").eq("nome", regional).maybeSingle();
    if (!reg) return json({ erro: "regional não encontrada" }, 400);
    const { data: existe } = await admin.from("perfis").select("id").eq("usuario", usuario).maybeSingle();
    if (existe) return json({ erro: "já existe um usuário com esse nome" }, 409);

    const { data: criado, error } = await admin.auth.admin.createUser({ email, password: senha, email_confirm: true });
    if (error || !criado.user) return json({ erro: error?.message ?? "falha ao criar usuário" }, 400);

    const { error: pErr } = await admin.from("perfis").insert({
      id: criado.user.id, usuario, papel: "regional", regional, trocar_senha: !!body.trocar_senha,
    });
    if (pErr) {
      await admin.auth.admin.deleteUser(criado.user.id);
      return json({ erro: pErr.message }, 400);
    }
    return json({ ok: true });
  }

  if (acao === "excluir" || acao === "senha") {
    const { data: alvo } = await admin.from("perfis").select("id, papel").eq("usuario", usuario).maybeSingle();
    if (!alvo) return json({ erro: "usuário não encontrado" }, 404);
    if (alvo.papel === "admin") return json({ erro: "o administrador não pode ser alterado por aqui" }, 400);

    if (acao === "excluir") {
      const { error } = await admin.auth.admin.deleteUser(alvo.id); // o perfil sai junto (on delete cascade)
      if (error) return json({ erro: error.message }, 400);
      return json({ ok: true });
    }

    const senha = String(body.senha ?? "");
    if (senha.length < 6) return json({ erro: "a senha precisa ter ao menos 6 caracteres" }, 400);
    const { error } = await admin.auth.admin.updateUserById(alvo.id, { password: senha });
    if (error) return json({ erro: error.message }, 400);
    await admin.from("perfis").update({ trocar_senha: body.trocar_senha !== false }).eq("id", alvo.id);
    return json({ ok: true });
  }

  return json({ erro: "ação desconhecida" }, 400);
});
