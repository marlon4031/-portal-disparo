# Portal de Solicitação de Envio em Massa · Security Solidez

Portal web (protótipo) para gestão de solicitações de disparo em massa via WhatsApp,
usado pelo ecossistema Universo AGV / Security Solidez.

## O que é

Aplicação **single-file** (`index.html`), sem servidor e sem dependências de build.
Os dados ficam salvos no navegador (localStorage). Abra o arquivo no navegador ou
publique no GitHub Pages.

## Funcionalidades

**Administrador**
- Login por usuário/senha; criação de acessos por regional (com opção de exigir troca de senha no 1º acesso)
- Templates: cadastro com categoria (Utilitário R$ 0,05 / Marketing R$ 0,33), busca por nome e regional, paginação, modal de detalhe
- Regionais: cadastro/edição, visão por regional (templates, filas e acessos), busca e paginação
- Filas de retorno: cadastro por regional, busca e paginação
- Solicitações: relógio de SLA por cor (verde até 20min, amarelo 20–40, vermelho 40+), ordenação (pendentes primeiro), filtro por status e regional, paginação, modal com download do CSV
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

## Publicar no GitHub Pages

1. Crie um repositório (ex.: `portal-disparo`).
2. Suba `index.html` e `README.md`.
3. Em **Settings → Pages**, selecione a branch `main` e a pasta `/root`.
4. Acesse a URL gerada (ex.: `https://SEU-USUARIO.github.io/portal-disparo/`).

## Observação importante

Este é um **protótipo**: os dados ficam no navegador de quem acessa (não há servidor
central). Para uso multiusuário real — cada regional no seu aparelho, dados
centralizados, entrega das solicitações em tempo real — é necessário um backend
(ex.: Supabase: autenticação + banco + storage).
