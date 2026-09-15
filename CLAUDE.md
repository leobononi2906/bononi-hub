# Hub Bononi — guia do projeto

> **Estado atual, pendências e dev-log: `docs/STATUS.md`.** Este arquivo é só o que é estável.
> Contexto do grupo e regras de banco: skill `bononi-contexto`. Rodar local: `rodar-app`.
> Publicar: `publicar-e-conferir`. Registrar o que foi feito: `registrar-status`.

## O que é

**Portal central de entrada do grupo.** Login unificado (Supabase Auth) e controle de quem acessa
qual app — é aqui que se libera e revoga acesso. Também tem o cadastro central de funcionários
(`rh_funcionarios`), troca de senha e indicadores.

## Onde está

- **Clone nesta máquina (`ecommerce06`):** `C:\Aplicações da bononi\bononi-hub` — é **este** que
  tem git. Qualquer outra pasta `bononi-hub\` solta é stub; na máquina do Leo o clone é
  `C:\CLAUDE\Projetos GitHub\bononi-hub\bononi-hub`.
- **Remote:** `leobononi2906/bononi-hub`, branch `main`. Push na `main` = produção.
- **Deploy:** https://bononi-hub.vercel.app
- **Supabase:** `vishxwdxqiygbxmtpfoy` — lê `vw_*`, `rh_*`, `integ_*`, `umbler_*`.
- **Local:** `preview_start { name: "hub" }` → porta 5286.

## Stack

HTML + JS puro, `index.html` único (~225 KB), sem build e sem `package.json`. Supabase por `fetch`
direto na REST. Design system da marca aplicado em 14/09/2026 (`ds/bononi-ds.css` + ponte de
variáveis no `:root`) — ver `docs/2026-09-14-design-system.md`.

## Armadilhas deste repo

- **Este app é o porteiro de todos os outros.** Quem entra em cada sistema é decidido por
  `user_metadata.modulos` gravado aqui. Um erro nesta tela tranca a operação inteira do grupo,
  não só o Hub — é o repo onde vale mais conferir antes de publicar.
- **Arquivo único de 225 KB**: `grep` antes de criar função, porque nome repetido não dá erro,
  só sobrescreve. Toda função chamada por `onclick` precisa estar exposta em `window.*`.
- **Ícone é hidratado por `MutationObserver`** (`[data-ic]` → CSS mask). Tela montada por
  `innerHTML` sem passar pelo observer fica sem ícone — e o token `--ic` é pintado em runtime por
  `setProperty`, então ele não aparece definido no CSS.
- **O `base.css` do pacote do DS estiliza `a` como link vermelho sublinhado** — aqui quase todo
  `a` é item de navegação ou cartão clicável. Não importe o `base.css` inteiro.
- Cor, fonte, raio e sombra **só por token** (`var(--action-primary)`, `var(--surface-card)`…).
  Ação primária é tinta `#14161a`, não vermelho. Auditar com a skill `aplicar-design-system`
  antes de publicar mudança visual.
