# Portal de Solicitação de Envio em Massa · Security Solidez

Portal web (protótipo) para gestão de solicitações de disparo em massa via WhatsApp,
usado pelo ecossistema Universo AGV / Security Solidez.

## O que é

Aplicação **single-file** (`index.html`), sem build, publicada no GitHub Pages.
Login, dados e planilhas ficam no **Supabase** (Auth + Postgres + Storage), então o
admin e cada regional, cada um no seu aparelho, veem os mesmos dados.

## Funcionalidades

**Administrador**
- Login por usuário/senha; criação, exclusão e troca de senha dos acessos por regional (com opção de exigir troca de senha no 1º acesso)
- Templates: cadastro com categoria (Utilitário R$ 0,05 / Marketing R$ 0,33), busca por nome e regional, paginação, modal de detalhe
- Regionais: cadastro/edição, visão por regional (templates, filas e acessos), busca e paginação
- Filas de retorno: cadastro por regional, busca e paginação
- Solicitações: relógio de SLA por cor (verde até 20min, amarelo 20–40, vermelho 40+), ordenação (pendentes primeiro), filtro por status e regional, paginação, modal com download do CSV e da planilha original
- Lista de solicitações atualiza em tempo real quando uma regional envia
- Consolidado por regional (solicitações, linhas, custo) com exportação

**Regional**
- Vê apenas os templates liberados para ela (em blocos, com busca)
- Sobe a planilha (xlsx/csv), escolhe a fila de retorno e (opcional) agenda
- Visualiza linhas, números únicos, custo aproximado e duplicados removidos (dedupe — Meta não permite 2 envios ao mesmo número)
- Acompanha o status das próprias solicitações (paginado) e baixa os últimos 60 dias

## Motor de processamento (embutido)

- Telefone: aceita 12/13 dígitos, normaliza com +55, mostra distribuição fixo/celular
- Placa → Chassi → `xxx-xxxx` (fallback)
- Limpeza de nome (remove prefixos CPF/CNPJ)
- Valor com ponto decimal; UTF-8-SIG; detecção de colunas por conteúdo
- Regra de day-delta para templates com "vence [n]"

## Arquivos

| Arquivo | O que é |
|---|---|
| `index.html` | O portal inteiro (interface + motor de processamento) |
| `config.js` | URL e chave pública do seu projeto Supabase |
| `supabase/schema.sql` | Tabelas, regras de acesso (RLS), bucket de arquivos e dados de exemplo |
| `supabase/functions/admin-usuarios/` | Edge Function que cria/exclui acessos (precisa da chave secreta, por isso roda no servidor) |

## Configurar o Supabase (uma vez)

1. **Crie o projeto** em [supabase.com](https://supabase.com) (o plano grátis serve).
2. **Banco:** abra *SQL Editor*, cole todo o conteúdo de `supabase/schema.sql` e clique em *Run*.
   Isso cria as tabelas `regionais`, `perfis`, `templates`, `filas` e `solicitacoes`,
   as regras de acesso, o bucket privado `planilhas` e alguns dados de exemplo.
3. **Login por usuário:** em *Authentication → Sign In / Providers → Email*, deixe o
   e-mail habilitado e **desligue "Confirm email"**. Em *Authentication → Settings*,
   desligue também **"Allow new users to sign up"**, para que só o admin crie acessos.
   (O portal usa o e-mail interno `usuario@disparo.local`; ninguém recebe e-mail.)
4. **Primeiro administrador:** em *Authentication → Users → Add user → Create new user*,
   use o e-mail `admin@disparo.local`, a senha que quiser e marque *Auto Confirm User*.
   Depois rode no *SQL Editor*:
   ```sql
   insert into public.perfis (id, usuario, papel)
   select id, 'admin', 'admin' from auth.users where email = 'admin@disparo.local'
   on conflict (id) do update set papel = 'admin';
   ```
   No portal, esse admin entra com usuário **admin**.
5. **Edge Function de acessos:** em *Edge Functions → Deploy a new function → Via Editor*,
   dê o nome `admin-usuarios`, cole o conteúdo de `supabase/functions/admin-usuarios/index.ts`
   e publique. (Ou, com a CLI: `supabase functions deploy admin-usuarios`.)
6. **Ligar o portal:** em *Project Settings → API*, copie a *Project URL* e a chave
   *anon / public* para o `config.js`. A chave anon é pública por design; **nunca**
   coloque a `service_role` nesse arquivo.

Pronto: entre como admin, cadastre os acessos das regionais na aba **Acessos** e mande
para cada regional o usuário e a senha.

### Quem vê o quê (RLS)

- **Admin:** vê e altera tudo.
- **Regional:** vê só os templates e filas liberados para ela, cria e acompanha só as
  solicitações da própria regional e só baixa os arquivos dessas solicitações.

### Retenção

O portal mostra os últimos 60 dias. As linhas e arquivos mais antigos continuam no
Supabase; se quiser apagar automaticamente, dá para agendar uma limpeza com `pg_cron`.

## Publicar no GitHub Pages

1. Crie um repositório (ex.: `portal-disparo`).
2. Suba `index.html`, `config.js` e `README.md`.
3. Em **Settings → Pages**, selecione a branch `main` e a pasta `/root`.
4. Acesse a URL gerada (ex.: `https://SEU-USUARIO.github.io/portal-disparo/`).
