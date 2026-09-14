# Bononi Hub

Porta de entrada única dos apps internos do **Grupo Bononi Acessórios**: login unificado
(Supabase Auth), controle de quem acessa qual app, e o centro de configuração do grupo
(funcionários, saúde da replicação do ERP, canais da Umbler, Integrador Bling→ERP).

| | |
|---|---|
| **Repositório** | https://github.com/leobononi2906/bononi-hub |
| **Produção** | https://bononi-hub.vercel.app |
| **Deploy** | Vercel automático — **`push` na `main` é publicar** |
| **Stack** | `index.html` único, sem build. Supabase por CDN. |
| **Banco** | Supabase `vishxwdxqiygbxmtpfoy` |

## Por onde começar

| Documento | O que responde |
|---|---|
| **[`docs/ARQUITETURA.md`](docs/ARQUITETURA.md)** | **Comece aqui.** O que o app faz, como se estrutura, modelo de acesso, tudo que lê e escreve, convenções, runbooks e armadilhas |
| [`docs/STATUS.md`](docs/STATUS.md) | Estado atual, pendências e dev-log — muda toda semana |
| [`docs/2026-09-14-design-system.md`](docs/2026-09-14-design-system.md) | Como o design system da marca foi aplicado |
| [`docs/UMBLER-FONTE-UNICA.md`](docs/UMBLER-FONTE-UNICA.md) | O projeto de intake único da Umbler |

## Rodar local

```bash
python "C:\Users\ecommerce06\Desktop\Aplicações Bononi\.claude\serve-staging.py" C:\APLICA~1\BONONI~4 5286
```

Sobe apontando pro **banco de teste**. O login não passa em local (as contas do Auth do Hub só
existem em produção) — ver "Rodar local" na [arquitetura](docs/ARQUITETURA.md) para inspecionar o
portal sem logar.

## Antes de mexer

- **`push` na `main` vai direto pra produção.** Não há staging deste app.
- **App novo entra em DUAS listas** no `index.html`: `APPS` e `MODULOS_LABELS`. Só numa gera bug
  silencioso.
- **Token de cor, nunca hex.** O único lugar com hex é `ds/bononi-ds.css`, que é gerado do pacote
  do design system e não se edita à mão.
- **Nada de `confirm()`/`alert()` nativos** — quebram no Safari do iOS. Use `bononiConfirmar()` e
  `bononiToast()`.
