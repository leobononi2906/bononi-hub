# Umbler — Config de Usuários + reestruturação do backend p/ análise (fase 2)

> Data: 2026-08-20 · Projeto Supabase `vishxwdxqiygbxmtpfoy` · App: `bononi-hub` (config) + camada de dados cross-app
> Continua o projeto **UMBLER-FONTE-UNICA.md** (intake, 30/07). Aqui é a camada de **gestão/análise** por cima do intake.

## Objetivo maior (por que isso existe)
Duas fases combinadas:
1. **Gestão** — saber *quem* é cada atendente da Umbler (de-para membro Umbler → pessoa do ERP).
2. **Análise** (fase 2) — analisar as próprias conversas, incluindo **qualidade das respostas** por atendente (ex.: equipe comercial). **Decisão do Leo 20/08:** por ora **estruturar o backend pra IA conseguir ler depois** — NÃO rodar IA ainda.

Sem o de-para membro→pessoa, todo relatório por atendente sai anônimo. E sem corrigir a estrutura das mensagens (abaixo), a IA leria dado errado.

---

## Parte A — Config de Usuários da Umbler (no Hub) ✅ NO AR

**O quê:** a aba Configuração do Hub tinha só **📡 Canais**. Agora o bloco Umbler tem subnavegação **📡 Canais | 👤 Usuários** (`setUmblerSub`). Usuários = cadastro do atendente.

**Por que o nome é manual:** o intake grava `id_membro_umbler` em toda mensagem, mas **`nome_atendente` vem SEMPRE nulo**. Então o admin digita o nome e vincula à pessoa do ERP.

**Backend (migração `umbler_usuarios_config`):**
- Tabela `public.umbler_usuarios` (PK `id_membro_umbler`): `nome`, `id_colaborador_erp` (→ `rh_funcionarios`), `nome_erp` (snapshot), `segmento`, `ativo`, `classificado_por`.
- Views: `vw_umbler_usuarios_resumo` (cadastro + volume real de msgs/último dia) e `vw_umbler_usuarios_nao_vinculados` (membro que respondeu ≤60d e não está no cadastro).
- RPCs `SECURITY DEFINER`: `umbler_classificar_usuario(p_id_membro,p_nome,p_id_colaborador_erp,p_segmento,p_por)` (upsert; resolve nome_erp) e `umbler_set_usuario_ativo`. Grants a anon+authenticated+service_role, **mesma postura das RPCs de canal**.
- **Seed:** trouxe 10 membros já conhecidos de `ecom_umbler_vendedor` + `atac_umbler_vendedor` (a tela não nasce vazia).

**Front (bononi-hub, `index.html` — ⚠️ clone aninhado `bononi-hub/bononi-hub/`):** `carregarUsuariosUmbler` / `renderUsuariosUmbler` / `salvarUsuarioUmbler` / `setUsuarioAtivo`; dropdown lê `rh_funcionarios?ativo=eq.true` (fonte canônica de gente). Funções em `window.*`. Filtros: Todos / Sem vínculo ERP / Inativos / **Não vinculados**.

**Estado:** deployado (commit `2ef01d9`, push main → Vercel). Restam **9 atendentes "não vinculados" com volume real** aguardando nome — 6 assistência, 1 ecom, **+ os 2 atendentes órfãos** `aTGhkpoXrJLt7_rY` / `aTG6AL5d9I0UBGsZ` que o BONONI_MASTER listava como pendência desde 15/06. Nomeá-los é ação de tela (o Leo faz).

**Não quebrou nada:** os mapas por app `atac_`/`ecom_`/`varejo_vendedor_umbler` (token de envio) seguem intactos. Migrar apps p/ a fonte unificada = passo futuro.

---

## Parte B — Reestruturação do backend das mensagens (base p/ IA) ✅ ESTRUTURA PRONTA

### O problema achado (diagnóstico)
A `umbler_mensagens` (populada pelo intake) tem **perda/erro** que impede análise séria:
1. **`direcao` (cliente/empresa) está ERRADA** — mislabela os ~18k do **BOT** (jogava mensagens automáticas como se fossem do cliente).
2. **Autor ≠ dono da conversa** — o `id_membro_umbler` da linha é o atendente **dono**; o **autor real** de uma resposta humana está noutro campo.
3. **Conteúdo majoritariamente em mídia sem texto** (áudio/imagem).

### A verdade é recuperável 100% do payload cru
`umbler_eventos.payload` é append-only e completo. Campos-chave em `$.Payload.Content.LastMessage`:
- **`Source`** = `Contact` (cliente) · `Member` (atendente humano) · `Bot` · `External` → **papel real**.
- **`SentByOrganizationMember.Id`** = **autor real** (só quando humano).
- **`File.{Url,ContentType,OriginalName,Transcription}`** = mídia (a `Url` é a que "vem nula" em ~⅓; `Transcription` é campo nativo Umbler mas **vem sempre null**).
- O `Content` (chat) ainda tem `ClosedAtUTC/ClosedBy/Open`, `FirstMemberReplyMessage`, `OrganizationMemberHistory` → fechamento e histórico de atendente recuperáveis (contorna o furo "ChatClosed não assinado" do master).

### A camada canônica criada (decisão: NOVA camada derivada do payload, NÃO corrigir o intake agora)
**Migração `umbler_msg_canonico`:**
- Tabela **`public.umbler_msg`** (1 linha/mensagem): `msg_id` (PK), `id_conversa`, `id_canal`, `segmento`, `source`, **`papel`** (cliente/atendente/bot/externo), **`autor_membro_id`** (→ `umbler_usuarios`), `id_contato`, `telefone`, `tipo`, `texto`, `tem_arquivo`, `arquivo_url`, `arquivo_tipo`, `arquivo_nome`, **`transcricao`**, `criada_em`, `event_id`. Índices por conversa, autor e papel.
- Função idempotente **`umbler_msg_backfill()`** — reconstrói/atualiza `umbler_msg` a partir do payload (pega o evento mais recente por `msg_id`; coalesce de url/transcrição/texto no conflito). Grant execute a authenticated+service_role.
- **Backfill rodou = 53.441 mensagens.** Papel bate com Source: cliente 20.716 · atendente 14.900 (15 autores) · bot 12.471 · externo 5.354.
- **Não-destrutiva:** não toca no intake nem na `umbler_mensagens`.

### Também criado (substrato de métrica objetiva)
- View **`vw_umbler_conversa_metricas`** (1 linha/conversa: msgs cliente/empresa, início/fim, duração, `tmr_min` = tempo até 1ª resposta, `primeiro_respondente`, `sem_resposta`, `aberta`).
- ⚠️ **Ela foi feita sobre a `umbler_mensagens`/`direcao` VELHA (furada)** — o TMR sai **bruto e inflado** (não desconta horário comercial nem separa a fase do bot). **Antes de virar KPI, REBASEAR na `umbler_msg`** (papel correto).

---

## Gaps para a IA "ler de fato" (frentes seguintes — nenhuma bloqueia o que já roda)
1. 🔴 **Transcrição** — `transcricao` vem **0** (Umbler não transcreve) e **a maioria das respostas de atendente é ÁUDIO** (9.262 de 14.900 são mídia). Precisa STT (áudio→texto) + visão/descrição (imagem) próprios, escrevendo em `umbler_msg.transcricao`. Padrão de referência: IA da Assistência (token no Vault, Edge Function).
2. **URL de mídia nula** (furo conhecido) — muitos áudios sem `File.Url` → só recuperável via API Umbler por id da mensagem.
3. **Manter `umbler_msg` fresca** — pôr `umbler_msg_backfill()` em **pg_cron** (recomendado; NÃO feito — cron é config permanente, pedir "pode"). Enquanto isso, rodar a função manualmente atualiza.
4. **View de transcript por conversa** p/ alimentar a IA — fácil, depois da transcrição.
5. **Corrigir o intake** (go-forward) p/ gravar papel/autor certos na origem — adiado de propósito (o payload cobre; a camada canônica se reconstrói dele).
6. **Onde a análise vai morar** — ainda **não decidido** (candidatos: aba no dashboard do Ecommerce, app novo dedicado, ou no Hub).

## Combustível de dados hoje (importante p/ escopo)
A "equipe comercial" com dado rico no modelo unificado é o **ecommerce** (3.037 conversas, 8 atendentes, desde 30/07) + assistência (584, desde 25/06). O **atacado quase não está no unificado** (94 conversas, só desde 17/08) porque ainda flui pelo `Dash_atacado` — a análise nasce onde tem combustível.

## Objetos criados nesta sessão (resumo)
| Objeto | Tipo | Migração |
|---|---|---|
| `umbler_usuarios` | tabela | `umbler_usuarios_config` |
| `vw_umbler_usuarios_resumo` / `_nao_vinculados` | views | `umbler_usuarios_config` |
| `umbler_classificar_usuario` / `umbler_set_usuario_ativo` | RPCs | `umbler_usuarios_config` |
| `vw_umbler_conversa_metricas` | view | `umbler_conversa_metricas` |
| `umbler_msg` | tabela | `umbler_msg_canonico` |
| `umbler_msg_backfill()` | função | `umbler_msg_canonico` |
