-- =====================================================================
-- Portal de Disparo · schema do Supabase
-- Rode este arquivo inteiro no SQL Editor do Supabase (uma vez).
-- Ele é idempotente: pode rodar de novo sem duplicar nada.
-- =====================================================================

-- ---------- tabelas ----------

create table if not exists public.regionais (
  nome       text primary key,
  criado_em  timestamptz not null default now()
);

-- perfil de cada login (1:1 com auth.users)
create table if not exists public.perfis (
  id           uuid primary key references auth.users(id) on delete cascade,
  usuario      text not null unique,
  papel        text not null check (papel in ('admin','regional')),
  regional     text,
  trocar_senha boolean not null default false,
  criado_em    timestamptz not null default now(),
  check (papel = 'admin' or regional is not null)
);

create table if not exists public.templates (
  id         uuid primary key default gen_random_uuid(),
  nome       text not null,
  texto      text not null,
  categoria  text not null default 'utilitario' check (categoria in ('utilitario','marketing')),
  regionais  text[] not null default '{}',
  criado_em  timestamptz not null default now()
);

create table if not exists public.filas (
  id         uuid primary key default gen_random_uuid(),
  nome       text not null unique,
  regionais  text[] not null default '{}',
  criado_em  timestamptz not null default now()
);

create table if not exists public.solicitacoes (
  id             uuid primary key default gen_random_uuid(),
  criado_em      timestamptz not null default now(),
  regional       text not null,
  usuario_id     uuid references auth.users(id) on delete set null default auth.uid(),
  usuario        text,
  template       text not null,
  arquivo        text,                -- nome da planilha original enviada
  linhas         integer not null default 0,
  custo          numeric(12,2) not null default 0,
  fila           text,
  agendado_para  timestamptz,
  status         text not null default 'Solicitado' check (status in ('Solicitado','Realizado')),
  realizado_em   timestamptz,
  csv_nome       text,                -- nome sugerido para download
  csv_path       text,                -- caminho do CSV gerado no bucket "planilhas"
  original_path  text                 -- caminho da planilha original no bucket
);

create index if not exists solicitacoes_criado_em_idx on public.solicitacoes (criado_em desc);
create index if not exists solicitacoes_regional_idx  on public.solicitacoes (regional);

-- ---------- funções auxiliares (usadas nas regras de acesso) ----------

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfis where id = auth.uid() and papel = 'admin');
$$;

create or replace function public.minha_regional() returns text
language sql stable security definer set search_path = public as $$
  select regional from public.perfis where id = auth.uid();
$$;

-- o próprio usuário marca que já trocou a senha do 1º acesso
create or replace function public.marcar_senha_trocada() returns void
language sql security definer set search_path = public as $$
  update public.perfis set trocar_senha = false where id = auth.uid();
$$;

-- renomeia uma regional em cascata (templates, filas, acessos e solicitações)
create or replace function public.renomear_regional(antigo text, novo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'apenas o administrador pode renomear regionais'; end if;
  novo := upper(trim(novo));
  if novo = '' then raise exception 'nome inválido'; end if;
  if exists (select 1 from public.regionais where nome = novo) then raise exception 'já existe uma regional com esse nome'; end if;
  insert into public.regionais (nome) values (novo);
  update public.templates    set regionais = array_replace(regionais, antigo, novo) where antigo = any(regionais);
  update public.filas        set regionais = array_replace(regionais, antigo, novo) where antigo = any(regionais);
  update public.perfis       set regional = novo where regional = antigo;
  update public.solicitacoes set regional = novo where regional = antigo;
  delete from public.regionais where nome = antigo;
end;
$$;

revoke all on function public.renomear_regional(text,text) from public, anon;
grant execute on function public.renomear_regional(text,text) to authenticated;
revoke all on function public.marcar_senha_trocada() from public, anon;
grant execute on function public.marcar_senha_trocada() to authenticated;

-- ---------- RLS (quem pode ver/editar o quê) ----------

alter table public.regionais    enable row level security;
alter table public.perfis       enable row level security;
alter table public.templates    enable row level security;
alter table public.filas        enable row level security;
alter table public.solicitacoes enable row level security;

-- regionais: todos os logados leem; só admin altera
drop policy if exists regionais_ler    on public.regionais;
drop policy if exists regionais_admin  on public.regionais;
create policy regionais_ler   on public.regionais for select to authenticated using (true);
create policy regionais_admin on public.regionais for all    to authenticated using (public.is_admin()) with check (public.is_admin());

-- perfis: cada um lê o seu; admin lê todos. Criação/exclusão só pela Edge Function (service role).
drop policy if exists perfis_ler on public.perfis;
create policy perfis_ler on public.perfis for select to authenticated using (id = auth.uid() or public.is_admin());

-- templates: regional lê os liberados para ela; admin faz tudo
drop policy if exists templates_ler   on public.templates;
drop policy if exists templates_admin on public.templates;
create policy templates_ler   on public.templates for select to authenticated using (public.is_admin() or public.minha_regional() = any(regionais));
create policy templates_admin on public.templates for all    to authenticated using (public.is_admin()) with check (public.is_admin());

-- filas: idem
drop policy if exists filas_ler   on public.filas;
drop policy if exists filas_admin on public.filas;
create policy filas_ler   on public.filas for select to authenticated using (public.is_admin() or public.minha_regional() = any(regionais));
create policy filas_admin on public.filas for all    to authenticated using (public.is_admin()) with check (public.is_admin());

-- solicitações: regional vê e cria as dela; admin vê e altera todas
drop policy if exists sol_ler            on public.solicitacoes;
drop policy if exists sol_criar          on public.solicitacoes;
drop policy if exists sol_admin_alterar  on public.solicitacoes;
drop policy if exists sol_excluir        on public.solicitacoes;
create policy sol_ler on public.solicitacoes for select to authenticated
  using (public.is_admin() or regional = public.minha_regional());
create policy sol_criar on public.solicitacoes for insert to authenticated
  with check (regional = public.minha_regional() and usuario_id = auth.uid() and status = 'Solicitado');
create policy sol_admin_alterar on public.solicitacoes for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
-- a regional só pode apagar uma solicitação dela ainda pendente (usado se o upload do arquivo falhar)
create policy sol_excluir on public.solicitacoes for delete to authenticated
  using (public.is_admin() or (regional = public.minha_regional() and usuario_id = auth.uid() and status = 'Solicitado'));

-- ---------- Storage: bucket privado "planilhas" ----------
-- Arquivos ficam em  <id da solicitação>/<arquivo>.  O acesso segue a solicitação.

insert into storage.buckets (id, name, public, file_size_limit)
values ('planilhas', 'planilhas', false, 52428800)  -- 50 MB por arquivo
on conflict (id) do nothing;

drop policy if exists planilhas_ler    on storage.objects;
drop policy if exists planilhas_enviar on storage.objects;
drop policy if exists planilhas_admin  on storage.objects;

create policy planilhas_ler on storage.objects for select to authenticated
  using (bucket_id = 'planilhas' and exists (
    select 1 from public.solicitacoes s
    where s.id::text = (storage.foldername(name))[1]
      and (public.is_admin() or s.regional = public.minha_regional())));

create policy planilhas_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'planilhas' and exists (
    select 1 from public.solicitacoes s
    where s.id::text = (storage.foldername(name))[1]
      and s.regional = public.minha_regional()
      and s.usuario_id = auth.uid()));

create policy planilhas_admin on storage.objects for delete to authenticated
  using (bucket_id = 'planilhas' and public.is_admin());

-- ---------- tempo real (admin vê novas solicitações na hora) ----------
do $$ begin
  alter publication supabase_realtime add table public.solicitacoes;
exception when duplicate_object then null; end $$;

-- ---------- dados iniciais (regionais, filas e templates de exemplo) ----------

insert into public.regionais (nome) values
  ('MG.56'),('MG.70'),('MG.97'),('MG.113'),('MG.120'),('MG.128'),('MG.129'),('MG.132'),('MT'),
  ('BA.24'),('BA.25'),('SE.04'),('SE.05'),('SP'),('PE.07'),('RJ.04'),('CE.01')
on conflict do nothing;

insert into public.filas (nome, regionais) values
  ('Retorno Cobrança',   '{MG.70,BA.25,MG.132,MG.113,SP}'),
  ('Retorno Reativação', '{RJ.04,MG.56}'),
  ('Atendimento Geral',  '{MG.56,MG.70,MG.97,MG.113,MG.120,MG.128,MG.129,MG.132,MT,BA.24,BA.25,SE.04,SE.05,SP,PE.07,RJ.04,CE.01}'),
  ('Retorno São João',   '{BA.25,SE.05}')
on conflict (nome) do nothing;

insert into public.templates (nome, regionais, categoria, texto)
select * from (values
  ('lembrete_vence', '{MG.70,BA.25,MG.132}'::text[], 'utilitario',
   E'Universo AGV\nOi, [1]! 😊\nSó passando pra lembrar que seu pagamento vence [2]!\n🚗 Placa: [3]\n💵 Valor: R$ [4]\n📆 Vencimento: [5]\n📄 Pague com a chave Pix 👇\n[6]\n📄 Link do boleto 👇\n[7]\n✅ Já realizou o pagamento?'),
  ('sao_joao', '{BA.25,SE.05}'::text[], 'marketing',
   E'Universo AGV\nOi, [1]! 🌽🎉\nCom as festas de São João chegando, lembramos que o pagamento da sua proteção vence em [2]! 😊\n🚗 Placa: [3]\n💵 Valor: R$ [4]\n📆 Vencimento: [5]\n📄 Pix 👇\n[6]\n📄 Boleto 👇\n[7]\n🔥 Aproveite o São João protegido!'),
  ('pendente', '{MG.113,MG.70}'::text[], 'utilitario',
   E'Oi, [1]!👋\nSeu pagamento está PENDENTE!⚠️\n🚗 Placa: [2]\n💵 Valor: [3]\n📆 Vencimento: [4]\n🔑Chave Pix👇:\n[5]\n📄 Link do Boleto👇\n[6]\nDúvidas? Estamos à disposição! 💬'),
  ('inadimplente', '{SP,MG.97}'::text[], 'utilitario',
   E'Universo AGV\nOlá, [1]! 👋\nIdentificamos uma PENDÊNCIA DE PAGAMENTO ⚠️\n💰 Valor: R$ [2]\n🚗 Veículo: [3]\n⚠️ Sua cobertura está TEMPORARIAMENTE SUSPENSA.\n💬 Precisa de ajuda?'),
  ('reativacao', '{RJ.04,MG.56}'::text[], 'marketing',
   E'Olá, [1]! 👋\nUniverso AGV.\nSua proteção está INATIVA.\n📋 Placa: [2]\nQue tal voltar a ficar protegido? Temos condições especiais! Responda SIM. 🚗✅')
) as v(nome, regionais, categoria, texto)
where not exists (select 1 from public.templates);

-- =====================================================================
-- PRIMEIRO ADMINISTRADOR
-- 1) No painel: Authentication → Users → Add user → Create new user
--      e-mail: admin@disparo.local   (o "usuário" no portal será "admin")
--      senha:  a que você quiser     · marque "Auto Confirm User"
-- 2) Depois rode só esta linha no SQL Editor:
--
--   insert into public.perfis (id, usuario, papel)
--   select id, 'admin', 'admin' from auth.users where email = 'admin@disparo.local'
--   on conflict (id) do update set papel = 'admin';
--
-- Os demais acessos (regionais) são criados pelo próprio portal, na aba Acessos.
-- =====================================================================
