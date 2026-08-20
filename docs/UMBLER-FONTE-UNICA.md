# Umbler — Fonte Única de Intake (projeto)

Documento de estado e handoff do projeto que muda como o Grupo Bononi recebe as
informações da **Umbler** (omnichannel/WhatsApp). Atualizado em 30/07/2026.

---

## 1. Objetivo

Antes: **um webhook (Edge Function) por setor**, cada um gravando nas suas
tabelas. Isso dificultava adicionar setores novos (ex.: **Financeiro**) e
consolidar dados.

Agora: **um receptor único** ("Aplicação Geral" na Umbler) que recebe **todos os
canais**, grava numa **fonte única** e depois **distribui** para cada setor.
A segmentação é **configurável** (canal → setor) por uma tela no hub.

Princípios fixos do projeto:
- **Config geral sempre no hub** (`bononi-hub`).
- **Canal só vive em UMA Aplicação da Umbler** (limitação atual da ferramenta).
- **Atacado é o setor crítico** — migrar por último, nunca quebrar.
- **Nada se perde**: todo evento é salvo cru (`umbler_eventos.payload` jsonb).

---

## 2. Arquitetura

```
Umbler (Aplicação "Geral", todos os canais)
        │  webhook
        ▼
  umbler-intake  ── grava ─▶ umbler_eventos / umbler_conversas / umbler_mensagens
        │                     (carimbados com `segmento`)
        │  roteia por segmento (PRÓXIMA ETAPA)
        ├─ assistencia ─▶ assistencia-umbler-webhook ─▶ assist_chamados / assist_followups
        ├─ ecommerce   ─▶ Ecomm_UMBLER              ─▶ ecom_leads / ecom_umbler_*
        ├─ atacado     ─▶ UMBLERATC                 ─▶ atac_umbler_*
        └─ pendente    ─▶ (só captura genérico; não roteia)
```

O **segmento** de cada evento é resolvido pelo de-para `umbler_canal_segmento`.
Canal novo aparece sozinho como `pendente` e é classificado na **tela do hub**.

### Decisão de design: roteador, não reescrita
Cada setor já tem uma função com lógica madura (ex.: a assistência busca cliente
por telefone, mapeia tag→status, trata número bloqueado, entrada/saída, followups).
Em vez de reescrever isso a partir das tabelas novas, o `umbler-intake`
**reencaminha o mesmo payload** para a função do setor conforme o segmento.
Cada setor continua rodando com a função dele **intacta** — só muda quem a chama.

---

## 3. O que já está NO AR (Supabase — projeto `vishxwdxqiygbxmtpfoy`)

### Tabelas (migration `umbler_intake_fonte_unica`)
- `umbler_eventos` — cru, recebe tudo, dedup por `event_id`, `payload` jsonb.
- `umbler_conversas` — conversa parseada (upsert por `id_conversa`) + `segmento`.
- `umbler_mensagens` — mensagem parseada (upsert por `event_id`) + `segmento`.
- `umbler_canal_segmento` — de-para canal→setor (configurável), auto-cadastro de
  canal novo como `pendente`, trigger de `atualizado_em`.

### Função de intake
- **`umbler-intake`** (`verify_jwt=false`) — receptor único.
  URL do webhook Geral:
  `https://vishxwdxqiygbxmtpfoy.supabase.co/functions/v1/umbler-intake`
  Fonte: `supabase/functions/umbler-intake/index.ts` (neste repo).

### Classificação (migration `umbler_classificar_canal_e_resumo`)
- `umbler_classificar_canal(p_id_canal, p_segmento, p_por)` — `SECURITY DEFINER`.
  Atualiza o de-para **e re-carimba o histórico** (eventos/conversas/mensagens)
  daquele canal. Grant de EXECUTE só para `authenticated`.
- View `umbler_canais_resumo` — canal + volume (mensagens/eventos/último) para a tela.

### Tela (hub)
- `index.html` do `bononi-hub`: botão **📡 Canais** (admin) → painel que lista os
  canais (pendentes no topo), classifica/edita o setor e salva via RPC
  `umbler_classificar_canal`. Lê a view `umbler_canais_resumo`.

Os SQLs completos estão em `supabase/migrations/` neste repo.

---

## 4. Estado atual dos canais (30/07/2026)

O webhook Geral já está recebendo. Snapshot:

| Canal | Setor real | Status |
|---|---|---|
| SUPORTE STONNI | assistência | **classificado** ✅ |
| ANA ATAC, ATACADO, GUILHERME ATAC, IGUI ATAC, JOÃO ATAC | atacado | pendente |
| OFICIAL LV, OFICIAL LF | ecommerce | pendente |

⚠️ **Risco aberto:** os canais do **atacado** e do **ecommerce** foram movidos
para a Aplicação Geral. Como canal só vive em uma Aplicação, eles **saíram** dos
webhooks antigos (`UMBLERATC`, `Ecomm_UMBLER`) → **o CRM do atacado e o dashboard
do ecommerce estão sem dado novo** até que:
- (a) o **roteador** esteja ativo para esses segmentos e os canais **classificados**; ou
- (b) os canais sejam **devolvidos** para as Aplicações antigas (Dash_atacado / Ecommdas).

Nada se perde nesse meio-tempo — tudo está cru em `umbler_eventos` e pode ser
**backfilled** (reprocessado) depois.

---

## 5. Próximos passos

1. **Roteador na assistência** (liberado): no `umbler-intake`, quando
   `segmento='assistencia'`, reencaminhar o payload para `assistencia-umbler-webhook`.
   Depois **backfill** dos eventos do SUPORTE STONNI que ficaram só no genérico
   (replay de `umbler_eventos.payload` onde `segmento='assistencia'`).
2. Validar `assist_chamados` voltando a popular.
3. Repetir para **ecommerce** (→ `Ecomm_UMBLER`) e, **por último**, **atacado**
   (→ `UMBLERATC`), cada um testado e com backfill.
4. **Financeiro**: setor novo, nasce direto nesse modelo (classificar o canal do
   financeiro → rotear para a função/tabela do financeiro a definir).

---

## 6. Pendências operacionais

- **Push do hub:** o ambiente da sessão de trabalho ficou com escopo de escrita só
  em `leobononi2906/assistencia`; o `bononi-hub` só pôde ser lido/clonado. Para o
  agente pushar direto, abrir a sessão já com `bononi-hub` no escopo de escrita.
  Enquanto isso, os arquivos são entregues prontos (e há um `git bundle` com os
  commits — ver `push/`).

---

## 6b. Camada de gestão/análise por cima do intake (20/08/2026)
Além do intake, foi construída a camada de **gestão de usuários** e a **reestruturação
do backend das mensagens** para análise (base p/ IA ler depois — a IA ainda NÃO roda):
- **Config de Usuários da Umbler** (subaba 👤 no Hub): de-para `id_membro_umbler → pessoa ERP`
  (`umbler_usuarios` + RPC `umbler_classificar_usuario`).
- **Camada canônica `umbler_msg`** (reconstruída de `umbler_eventos.payload`): corrige o
  **papel** (cliente/atendente/bot/externo, via `Source`) e o **autor real**
  (`SentByOrganizationMember`) que a `umbler_mensagens`/`direcao` erra. Função
  `umbler_msg_backfill()`.
- ⚠️ **Não usar `umbler_mensagens`/`direcao` para análise** — mislabela o bot e confunde
  autor com dono da conversa. Usar `umbler_msg`.

Detalhes completos, diagnóstico e próximos passos (transcrição de áudio/imagem):
**`docs/2026-08-20-umbler-usuarios-e-analise-backend.md`**.

---

## 7. Convenções

- Tabelas genéricas da Umbler: prefixo `umbler_`.
- Setores mantêm seus prefixos: `assist_`, `ecom_`, `atac_`, `varejo_`, `fin_`.
- Segmentos válidos: `atacado | varejo | assistencia | financeiro | ecommerce | pendente`.
