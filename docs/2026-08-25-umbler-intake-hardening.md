# Umbler intake — incidente de pausa (17–24/08) + hardening v7

> 25/08/2026 · Supabase `vishxwdxqiygbxmtpfoy` · função `umbler-intake`
> Continua `UMBLER-FONTE-UNICA.md`.

## O que aconteceu (incidente)
- **17/08 21:04 o `umbler-intake` parou** de gravar. Ficou **6 dias parado (18–23/08)**; voltou 24/08 quando o Leo **reativou o webhook** no painel da Umbler.
- **Causa:** o Umbler **auto-pausa** um webhook que responde devagar/falha sob carga. O ecommerce entrou na fonte única ~14–15/08 e o volume explodiu (**17/08 = 7.631 eventos/dia**, ~5k de ecommerce). A v6 do intake era **síncrona**: esperava resolver segmento + gravar `umbler_eventos` + `umbler_conversas` + `umbler_mensagens` + **chamar a função do setor e esperar ela terminar** (a da assistência faz busca de telefone full-scan) ANTES de responder. Sob esse volume ficou lenta → Umbler pausou.
- **Atacado não parou** porque a `UMBLERATC`/`Dash_atacado` é webhook separado (não foi pausado).
- **O buraco 18–23/08 NÃO foi reenviado** pelo Umbler (6 dias vazios em `umbler_eventos`). Assistência+ecommerce desses dias se perderam do nosso lado — só recuperável via **API do Umbler** (não temos puxador). O atacado do período está salvo no CRM dele.

## O conserto (v7, no ar 25/08)
Padrão de webhook robusto: **responder 200 na hora, processar o pesado em background.**
- Resolve segmento + grava **só `umbler_eventos`** (1 upsert, rápido) e **responde 200 imediatamente** → "nada se perde" (o cru já está salvo) e o Umbler nunca mais vê lentidão.
- `umbler_conversas`, `umbler_mensagens` e o **roteamento pros setores** (assistencia→`assistencia-umbler-webhook`, ecommerce→`Ecomm_UMBLER`, atacado→`UMBLERATC`) rodam em **background** via `EdgeRuntime.waitUntil`.
- **Catch responde 200 (`ok:false`) em vez de 500** — uma falha pontual não pausa mais o webhook.
- Backup da v6: `supabase/functions/umbler-intake/index.ts.bak-v6-20260825` (restaurar = re-deploy desse conteúdo).

**Validado (25/08 ~12:55):** `umbler_eventos`/`umbler_mensagens`/`umbler_conversas` gravando ao vivo + os 3 CRMs distribuindo (`ecom_leads`, `assist_chamados`, `atac_umbler_contatos`). Deploy via Supabase MCP (verify_jwt=false); fonte versionada (commit `3f3d27c`).

## Pendências
1. **Buraco 18–23/08:** só via API Umbler (falta token/puxador). Confirmar se ainda vale recuperar.
2. **Monitoramento:** criar alarme se `umbler_eventos` ficar > X min sem evento (pra pegar uma pausa futura no mesmo dia, não 6 dias depois). Sugerido: view + cron tipo `vw_rep_saude`.
3. **Análise:** usar `umbler_msg` (papel/autor corretos), não `umbler_mensagens/direcao`. Manter `umbler_msg_backfill()` fresco (cron — pedir "pode").
