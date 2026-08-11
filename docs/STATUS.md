# STATUS — Bononi Hub (porteiro / liberação de acessos)

> Atualizado: 2026-08-11

## O que é
Portal central de entrada do grupo. **Login unificado** (Supabase Auth) e **controle de quem acessa qual app**. É aqui que se liberam/revogam acessos. Também tem cadastro central de Funcionários (`rh_funcionarios`), troca de senha e um indicador de sync do ERP.

## Onde está
- **Clone real (git):** C:\CLAUDE\Projetos GitHub\bononi-hub\bononi-hub  (remote `leobononi2906/bononi-hub`, branch `main`)
  ⚠️ A pasta externa `bononi-hub\` é stub solto (sem git) — não editar lá.
- **Deploy:** https://bononi-hub.vercel.app · **push na `main` = produção** (Vercel auto).
- **Código:** `index.html` (app inteiro, ~1530 linhas). Anon key exposta é por design.

## 🔑 Modelo de acesso
Acesso mora no `user_metadata` do usuário: **`modulos`** (array de chaves) + **`admin: true`** (acessa tudo). Cada app checa a SUA chave no login.

### 13 chaves → app (⚠️ chave ≠ nome do app em 3 casos)
financeiro→Dashboard · compras · assistencia · cobranca · ecommerce · **atacado→CRM** · **stonni→Portal Rep** · frete · loja · operacoes · expedicao · rede-autorizada · **varejo→Consulta Vendas**.
Fonte da verdade: listas `APPS` + `MODULOS_LABELS` no `index.html` — **app novo entra nos DOIS**.

## Como se libera/revoga (só admin)
Botões ⚙️ Usuários / 👥 Funcionários. Listar: RPC `admin_listar_usuarios`. Editar acesso: RPC `admin_atualizar_usuario(p_uid, p_meta)` grava `{nome,admin,modulos,email_verified}`. Criar/deletar/resetar senha: Edge `admin-usuarios` (service_role). Revogar = desmarcar módulo e salvar.

## Estado atual
Em produção. Telas: Login · Portal (grid de apps por permissão) · Admin Usuários · modal Editar/Criar usuário · modal Minha Senha · modal Funcionários · indicador+modal de Sync ERP.

## Pendências / próximos passos
- [ ] Confirmar caminho de deploy (agora clonado; validar que Vercel puxa do GitHub `main`).
- [ ] `confirm()` nativo em deletarUsuario/toggleAtivoFunc — trocar por modal HTML (bononi-padrao §3.6) quando mexer nessas telas.
- [ ] `financeiro`: nota "atualizar quando dasu_financeiro estiver no ar" — verificar.

## Dívidas e armadilhas conhecidas
- Chave de acesso ≠ nome do app (stonni/varejo/atacado). App novo entra em `APPS` **e** `MODULOS_LABELS`.
- `admin-usuarios` é Edge deploy-only (não está no repo); `admin_*` são RPCs no Supabase.
- Arquivo único grande — quebra gradual ao mexer.

## Dev-log
- 2026-08-11 — **Revisão de layout (todas as telas):** o Hub era tema claro com resíduos de tema escuro que quebravam a leitura. Corrigido: modal Editar Usuário era fundo escuro `#111F33` com inputs de texto escuro (texto sumia) → agora card claro; inputs do login/senha/funcionários com fundo `rgba(255,255,255,.04)` invisível no branco → `var(--input-bg)`; textos de erro/sucesso (`#fca5a5`/`#6ee7b7`) e empty/loading em cor clara sobre fundo claro → tokens `--destructive`/`--success`/`--muted`; bordas brancas-transparentes → `var(--border)`; sombras pesadas `rgba(0,0,0,.5)` → sombras Bononi suaves. Adicionados tokens de estado no `:root`. **Melhorias:** busca no painel de Usuários (input `admin-busca` que faltava), saudação do login dinâmica (Bom dia/Boa tarde/Boa noite). Também trocada a URL da Cobrança no catálogo: Lovable → `bononi-cobranca.vercel.app`. Validado node --check (sintaxe OK).
