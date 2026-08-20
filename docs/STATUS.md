# STATUS — Bononi Hub (porteiro / liberação de acessos)

> Atualizado: 2026-08-18

## O que é
Portal central de entrada do grupo. **Login unificado** (Supabase Auth) e **controle de quem acessa qual app**. É aqui que se liberam/revogam acessos. Também tem cadastro central de Funcionários (`rh_funcionarios`), troca de senha e um indicador de sync do ERP.

## Onde está
- **Clone real (git):** C:\CLAUDE\Projetos GitHub\bononi-hub\bononi-hub  (remote `leobononi2906/bononi-hub`, branch `main`)
  ⚠️ A pasta externa `bononi-hub\` é stub solto (sem git) — não editar lá.
- **Deploy:** https://bononi-hub.vercel.app · **push na `main` = produção** (Vercel auto).
- **Código:** `index.html` (app inteiro, ~1930 linhas). Anon key exposta é por design.

## 🔑 Modelo de acesso
Acesso mora no `user_metadata` do usuário:
- **`modulos`** (array de chaves) = apps que o usuário acessa.
- **`admin: true`** = admin GLOBAL (acessa e administra tudo).
- **`admin_modulos`** (array de chaves, desde 11/08/2026) = apps em que o usuário é **admin daquele app** (só faz sentido se a chave também está em `modulos`). *Enforcement é "só centralizar no Hub": os apps passam a ler `admin_modulos` quando forem tocados; hoje o Hub gerencia/mostra o dado.*

Cada app checa a SUA chave no login.

### 13 chaves → app (⚠️ chave ≠ nome do app em 3 casos)
financeiro→Dashboard · compras · assistencia · cobranca · ecommerce · **atacado→CRM** · **stonni→Portal Rep** · frete · loja · operacoes · expedicao · rede-autorizada · **varejo→Consulta Vendas**.
Fonte da verdade: listas `APPS` + `MODULOS_LABELS` no `index.html` — **app novo entra nos DOIS**.

## Como se libera/revoga (só admin)
Botões ⚙️ Usuários / 👥 Funcionários. Listar: RPC `admin_listar_usuarios` (devolve `admin_modulos` desde 11/08). Editar acesso: RPC `admin_atualizar_usuario(p_uid, p_meta)` grava `{nome,admin,modulos,admin_modulos,email_verified}` (agora com **merge** `||`, não sobrescreve mais o metadata inteiro). Criar/deletar/resetar senha: Edge `admin-usuarios` (service_role). Revogar = desmarcar módulo e salvar.

No modal, cada módulo tem um toggle **🛡️ admin** (só habilita se o acesso estiver marcado) → grava em `admin_modulos`. Painel colapsável **"Admins por aplicação"** (`renderAdminsPorApp`) mostra admins globais + admins próprios de cada app.
⚠️ **Edge `admin-usuarios` (criar) é deploy-only e ainda NÃO grava `admin_modulos`** → em usuário NOVO, definir o admin-por-app numa edição seguinte (a RPC de update grava). Atualizar a Edge é item futuro.

## Estado atual
Em produção. Telas: Login · Portal (grid de apps por permissão) · Admin Usuários · modal Editar/Criar usuário · modal Minha Senha · modal Funcionários · indicador+modal de Sync ERP.

## Pendências / próximos passos
- [ ] (Futuro) Atualizar a Edge `admin-usuarios` p/ aceitar `admin_modulos` na criação.
- [ ] (Futuro/enforcement) Cada app ler `admin_modulos` p/ liberar suas telas de admin.
- [ ] `financeiro`: nota "atualizar quando dasu_financeiro estiver no ar" — verificar.
- [x] Achatar a pasta: raiz solta do Hub limpa em 11/08 (só clone + backups `push/`/`.zip`).

## Feito
- [x] **Umbler → subaba Usuários (20/08)** — o bloco Umbler da Configuração virou 2 subabas (**📡 Canais** | **👤 Usuários**). Usuários = cadastro unificado do atendente (membro Umbler) → pessoa do ERP, base dos relatórios por atendente. Ver dev-log 20/08.
- [x] **Aba Configuração (18/08)** — botão `🛠️ Configuração` (só admin) abre painel com 2 seções: **Saúde da replicação** (lê `vw_rep_saude` + `vw_rep_status` do replicador próprio) e **Canais Umbler** (classifica canal→segmento via RPC `umbler_classificar_canal`, sobre `umbler_canais_resumo`). O indicador de sync do topo foi **repontado** da heurística das 5 views (que ainda falava do sync Go morto "00:30 / fim de semana") para `vw_rep_saude`, monitorado 24/7.
- [x] **Admin por aplicação** — front (commit 9f52ccd) + RPCs aplicadas via apply_migration 11/08 (`admin_listar_usuarios` devolve `admin_modulos`; `admin_atualizar_usuario` faz merge). Verificado: 45 users, 4 já com admin_modulos.
- [x] Deploy confirmado: git → push `main` → Vercel.
- [x] `confirm()`/`alert()` nativos → modal (`bononiConfirmar`) + toast (`bononiToast`).
- [x] Painel Usuários agrupado (Internos / Representantes / Rede Autorizada).

## Dívidas e armadilhas conhecidas
- Chave de acesso ≠ nome do app (stonni/varejo/atacado). App novo entra em `APPS` **e** `MODULOS_LABELS`.
- `admin-usuarios` é Edge deploy-only (não está no repo); `admin_*` são RPCs no Supabase.
- Arquivo único grande — quebra gradual ao mexer.

## Dev-log
- 2026-08-20 — **Umbler fase 2: reestruturação do backend p/ análise (base IA, sem rodar IA).** Diagnóstico: `umbler_mensagens`/`direcao` é furada (mislabela os ~18k do BOT; confunde autor com dono da conversa). Verdade recuperável 100% de `umbler_eventos.payload` (`Source`/`SentByOrganizationMember`/`File`). Criada **camada canônica `umbler_msg`** (migração `umbler_msg_canonico`): papel cliente/atendente/bot/externo, autor real (→`umbler_usuarios`), mídia+`transcricao`, função idempotente `umbler_msg_backfill()`. Backfill = **53.441 msgs** (papel bate com Source; atendente=14.900/15 autores). Também `vw_umbler_conversa_metricas` (métrica por conversa — mas feita sobre a `direcao` velha, **rebasear em `umbler_msg` antes de virar KPI**). NÃO-destrutivo (não toca intake/umbler_mensagens). **Gaps p/ IA ler:** transcrição de áudio/imagem (Umbler não transcreve; maioria das respostas é áudio), URL de mídia nula, cron do backfill (a pedir), definir onde a análise mora. Detalhe completo: `docs/2026-08-20-umbler-usuarios-e-analise-backend.md`.
- 2026-08-20 — **Umbler: subaba Usuários (config de atendente).** O bloco Umbler da Configuração ganhou subnavegação **📡 Canais | 👤 Usuários** (`setUmblerSub`), Canais intacto. **Usuários** cadastra cada atendente (chave = `id_membro_umbler`, que a intake já grava em toda msg/conversa — mas `nome_atendente` vem sempre nulo, por isso o nome é manual). Vincula à pessoa do ERP via dropdown de `rh_funcionarios` (ativos) e a um segmento. Filtros Todos/Sem vínculo ERP/Inativos/**Não vinculados** (membro que respondeu nos últimos 60d e não está no cadastro). Backend novo (migração `umbler_usuarios_config`): tabela `umbler_usuarios`, views `vw_umbler_usuarios_resumo` (cadastro + volume real de msgs) e `vw_umbler_usuarios_nao_vinculados`, RPCs `umbler_classificar_usuario` (upsert, resolve nome_erp) e `umbler_set_usuario_ativo` — mesma postura/grants das RPCs de canal. **Seed** trouxe 10 membros já conhecidos dos mapas por app (`ecom_umbler_vendedor`+`atac_umbler_vendedor`); restam **9 não vinculados** com volume real (6 assistência, 1 ecom, +os 2 atendentes órfãos `aTGhkpoXrJLt7_rY`/`aTG6AL5d9I0UBGsZ` que o BONONI_MASTER arrastava desde 15/06). **Objetivo maior:** esta é a fundação da fase 2 = análise das conversas + qualidade de resposta por atendente (equipe comercial). **Motivo de existir:** sem o de-para membro→pessoa, todo relatório por atendente fica anônimo; e unifica o que estava fragmentado em 3 mapas por app. Verificado: RPC ponta-a-ponta (`ok:true`, resolve nome ERP completo), `rh_funcionarios` legível por anon/authenticated, `node --check` OK. **NÃO deployado ainda** (index.html modificado, sem commit/push) — o front não sobe até o push na main. Mapas por app `atac_`/`ecom_` seguem intactos (nada quebrado); migrar apps p/ a fonte unificada é passo futuro.
- 2026-08-18 — **Canais Umbler: gestão da lista.** Aba Canais ganhou 4 filtros (Todos/Pendentes/Inativos/Não vinculados). **Remover** (ativo=false) / **Restaurar** (ativo=true) via RPC nova `umbler_set_canal_ativo` (migração `umbler_gestao_lista_canais`). Aba **Não vinculados** = canais com contato nos últimos 60 dias que NÃO estão no de-para (view nova `vw_umbler_canais_nao_vinculados`) + botão "Adicionar à lista" (entra como pendente via `umbler_classificar_canal`). "Todos" agora mostra só ativos. Verificado no ar (anon): round-trip remover/restaurar OK, 0 não-vinculados hoje (rede de segurança). Commit 9b73a62.
- 2026-08-18 — **Aba Configuração + indicador de sync repontado.** O Hub virou o centro de configuração do cérebro. Nova aba (admin) `🛠️ Configuração` com: (1) **Saúde da replicação** — banner OK/ATRASO/ERRO lendo `vw_rep_saude` + tabela por objeto lendo `vw_rep_status` (grupo, linhas, última execução, situação); (2) **Canais Umbler** — lista `umbler_canais_resumo` (nome, volume msg/ev, último, quem classificou), dropdown de segmento (atacado/varejo/assistencia/financeiro/ecommerce/pendente) + Salvar que chama a RPC `umbler_classificar_canal` (re-carimba o histórico do canal no banco), com filtro Todos/Pendentes. O **indicador de sync do topo** e seu modal foram migrados da heurística antiga (5 views, ≤24h, lógica de fim de semana, texto "sync 00:30" do Go morto) para `vw_rep_saude`/`vw_rep_status` — agora reflete o replicador próprio, 24/7. Verificado no ar (anon SELECT nas views): banner "Tudo funcionando · há 1 min", 31 objetos no status, 10 canais renderizados. `node --check` OK. **Pendente:** a padronização da Umbler em si (abaixo) e avisar o Cauã que os canais saíram da mão dele. Backend já existia (`umbler-intake` + migrations 0001/0002).
- 2026-08-11 — **Admin por aplicação (`admin_modulos`):** novo campo no `user_metadata` = apps que o usuário administra (≠ admin global). Modal ganhou toggle 🛡️ admin por módulo (só habilita com o acesso marcado); lista destaca os módulos-admin; painel colapsável "Admins por aplicação" (globais + por app). RPCs alteradas: `admin_listar_usuarios` devolve `admin_modulos`; `admin_atualizar_usuario` passou a **mesclar** o metadata (para de apagar chaves de outros apps). Enforcement = só centralizar no Hub (apps leem depois). Front commit 9f52ccd; RPCs aplicadas via apply_migration (`hub_admin_modulos_rpcs`) — verificado no banco. Validado node --check.
- 2026-08-11 — **Painel Usuários por grupos:** internos, representantes (módulo `stonni`) e rede autorizada (`rede-autorizada`) estavam embolados (a rede até era escondida). Agora `classificarUsuario()` separa em 3 grupos; chips de filtro com contagem (default Internos), busca mantida, etiqueta de tipo na visão "Todos". **UX:** `confirm()`/`alert()` nativos → `bononiConfirmar()` (modal) + `bononiToast()`. **Repo:** versionado `supabase/` (edge umbler-intake + migrations), README e `docs/UMBLER-FONTE-UNICA.md` que só existiam na pasta solta. Commits 91ee9d5.
- 2026-08-11 — **Revisão de layout (todas as telas):** o Hub era tema claro com resíduos de tema escuro que quebravam a leitura. Corrigido: modal Editar Usuário era fundo escuro `#111F33` com inputs de texto escuro (texto sumia) → agora card claro; inputs do login/senha/funcionários com fundo `rgba(255,255,255,.04)` invisível no branco → `var(--input-bg)`; textos de erro/sucesso (`#fca5a5`/`#6ee7b7`) e empty/loading em cor clara sobre fundo claro → tokens `--destructive`/`--success`/`--muted`; bordas brancas-transparentes → `var(--border)`; sombras pesadas `rgba(0,0,0,.5)` → sombras Bononi suaves. Adicionados tokens de estado no `:root`. **Melhorias:** busca no painel de Usuários (input `admin-busca` que faltava), saudação do login dinâmica (Bom dia/Boa tarde/Boa noite). Também trocada a URL da Cobrança no catálogo: Lovable → `bononi-cobranca.vercel.app`. Validado node --check (sintaxe OK).
