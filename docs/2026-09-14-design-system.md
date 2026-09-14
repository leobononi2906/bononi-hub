# Design System Bononi aplicado no Hub — 14/09/2026

## O que foi feito
O Hub saiu do visual azul/`Syne`+`DM Sans` e passou a consumir o **Design System Bononi
Acessórios** (pacote recebido em `Bononi Acessórios Design System.zip`). É mudança **só de
camada visual** — nenhuma query, RPC, regra de acesso ou fluxo foi alterado.

## O que entrou no repo
| Caminho | O que é |
|---|---|
| `ds/bononi-ds.css` | **Gerado** do pacote do DS: `tokens/{colors,typography,spacing,radius,elevation,motion,base}.css` concatenados. Não editar à mão — regerar do pacote. |
| `assets/logo-bononi.png` · `logo-bononi-reverse.png` · `mark-bononi.png` | Logotipo oficial do DS (substituiu a marca-placeholder em SVG que o Hub desenhava inline). |

> **Por que concatenado e não `styles.css` com `@import`.** O `styles.css` do pacote é só uma
> lista de `@import` — 8 requisições encadeadas, que bloqueiam a pintura. Num portal isso é
> FOUC garantido. O conteúdo é idêntico; só a entrega mudou. As **fontes** saíram do
> `@import` e viraram `<link>` no `<head>` (com `preconnect`), pelo mesmo motivo.

## O que mudou no `index.html`

### 1. Camada de tokens
O bloco `:root` antigo virou uma **ponte**: cada nome antigo (`--blue`, `--muted`, `--surface`,
`--shadow`, `--border-radius-lg`…) agora aponta para o token semântico do DS. Isso fez as ~3.000
linhas de `style` inline herdarem a paleta nova sem reescrever uma por uma.

Mapeamento que importa entender:
- **`--blue` → `var(--action-primary)` (tinta `#14161a`).** No DS a ação primária é **tinta, não
  vermelha** — o logotipo já é preto e vermelho, e se todo botão fosse vermelho o destaque
  sumiria. O vermelho `#c11f25` ficou como **acento, um por tela**.
- `--surface2`/`--bg2` → `--surface-sunken`; `--dim` → `--text-faint`; `--success`/`--warning`/
  `--destructive` → os trios `--status-*-text` / `--status-*-bg`.

**Código novo deve usar o token do DS direto**, não a ponte.

### 2. Varredura de literais (702 ocorrências)
Não sobrou hex nem rgba solto no corpo do app — o único lugar com hex é `ds/bononi-ds.css`.
- fontes: `'DM Sans'` → `var(--font-ui)` (Barlow) · `'Syne'` → `var(--font-display)` (Archivo) ·
  `'DM Mono'` → `var(--font-mono)` (IBM Plex Mono)
- raios normalizados na escala do DS: 3px chip · 5px controle · 8px cartão/modal (o app tinha
  6/7/8/9/10/11/12/14/16/18/20px)
- escala tipográfica virou token (`--fs-11`…`--fs-24`); `10px`/`10.5px` subiram pra 11px, que é o
  piso do DS pra rótulo
- sombras viraram os 4 degraus do DS; scrims viraram `var(--scrim)`
- **gradientes eliminados** (18) — o DS proíbe gradiente nos sistemas internos; botão de ação
  virou tinta sólida

### 3. Emoji → ícones de verdade (152 ocorrências)
O DS é explícito: *"Emoji: nunca"* e *"`→`, `✓`, `●` não substituem glifos"*. Entrou o set
**Lucide** (o substituto oficial do DS enquanto não houver o set da casa), pintado como **CSS
mask** pra herdar `currentColor`:

```html
<i class="ic" data-ic="users"></i>          <!-- markup -->
${ic('users')}                               <!-- dentro de template string -->
```

Um `MutationObserver` hidrata os ícones sozinho. Isso importa: o Hub monta tela com `innerHTML`
em ~40 pontos diferentes, e sem o observer seria preciso lembrar de hidratar em cada um.

Onde o emoji era `textContent` (não aceita HTML), ele simplesmente **caiu** e ficou o rótulo
— `'✓ Salvo'` → `'Salvo'`, `'⏳ Reprocessando…'` → `'Reprocessando…'`. As setas `→` **em prosa**
("Bling → ERP", "Firebird → Supabase") ficaram: são tipografia, não ícone.

### 4. Componentes alinhados ao DS
- **Topbar** branca, hairline, `shadow-sticky`, logotipo real, avatar em tinta.
- **Tabs**: as subabas do Integrador **e** as da Umbler agora usam o mesmo padrão — rule
  vermelho de 2px embaixo da ativa. (A da Umbler era pílula preenchida, destoava.)
- **Cards de app**: hairline + raio 8 + `shadow-card`; hover vai um degrau mais escuro
  (`--surface-hover`), sem levitar. Tile do ícone neutro; no hover vira tinta.
- **Botões**: `primary` tinta · `accent` vermelho · `secondary` contorno · `danger` contorno
  vermelho. Press = `translateY(1px)`, sem escala.
- **Foco em tinta**, nunca azul (`0 0 0 2px #fff, 0 0 0 4px #14161a`).
- **Tabela**: cabeçalho caixa-alta sobre `surface-sunken`, hover na linha inteira em 80ms.
- Sumiram os `.orb` (glow) e a textura de ruído — o DS pede fundo sólido.

### 5. Decisões que valem discutir
- **Tiles de ícone dos apps ficaram neutros.** Eram 8 matizes (`.ic-blue`, `.ic-green`…). O DS
  limita a tela a duas cores de fundo e reserva cor pra significado. Se a cor por app fizer falta
  pra achar o app rápido, dá pra voltar mexendo só nas classes `.ic-*` — elas continuam no CSS,
  hoje todas apontando pro mesmo cinza.
- **Um vermelho por tela.** O overline da página ("BOM DIA", "INTEGRADOR", "CONFIGURAÇÃO") é o
  acento; o nome na saudação ficou em tinta.
- **No celular a barra de ferramentas vira ícone puro** (rótulo no `title`/`aria-label`). Antes
  os 6 botões quebravam em 3 linhas e comiam ~300px de altura.

### 6. Duas armadilhas da varredura hex→token (pegas na revisão, antes de subir)

Valem pros próximos apps, porque são do método, não deste arquivo:

**a) Alpha concatenado em hex quebra calado.** O app tinha três lugares fazendo
`background:${cor}18` / `${cor}14` / `${cor}0D` — hex + dois dígitos de alpha. Com a cor virando
`var(--status-ok-text)`, isso vira `var(--status-ok-text)18`: CSS inválido, declaração
descartada, **o fundo some sem erro nenhum**. Atingia o banner de saúde da replicação e os chips
de situação. A correção segue o DS de qualquer forma: par `{fg, bg}` com o tint sólido
(`--status-*-bg`) e texto em opacidade cheia — *"nunca `color-mix` ou alpha"*.
Como achar: `grep -n '\${[a-zA-Z_.]*}[0-9a-fA-F]\{2\}'`.

**b) Cores distintas colapsando no mesmo token.** Onde a cor **carrega informação** — mapa de
categoria, etiqueta de tipo — dois hex diferentes podem cair no mesmo alias semântico e a
distinção morre. Aconteceu em dois lugares: `UMBLER_SEG_COR` (atacado `#1A3A8F` e varejo
`#0077CC` viraram o mesmo azul — e essa cor é o ponto de 8px que identifica o segmento do canal)
e nas etiquetas Interno/Representante. Resolvido puxando da rampa base do DS
(`--bnn-blue-500`, `--bnn-ink-900`, `--bnn-green-500`, `--bnn-amber-500`, `--bnn-gray-600`,
`--bnn-gray-400`), que dá seis valores distinguíveis sem inventar um segundo vermelho.
Como achar: diff alinhado, procurando linha que tinha ≥2 hex distintos e ficou com menos tokens
distintos.

### 7. Consertado de passagem
`background:var(--card)` no botão "Usar padrão da empresa" — `--card` nunca existiu no arquivo,
então o botão ficava sem fundo. Virou `var(--surface-card)`.

## Pendências herdadas do pacote do DS
1. **Fonte da marca.** Archivo/Barlow/IBM Plex Mono são substitutos do Google Fonts. Se a Bononi
   tiver fonte licenciada, troca no `<link>` e em `tokens/typography.css`.
2. **Ícones.** Lucide é substituto, servido pela CDN `unpkg` com versão fixada (`0.544.0`). Se
   aparecer o set da casa, muda só a constante `LUCIDE` no topo do `<script>`.
3. **Logotipo vetorial.** Só temos PNG; o SVG/AI evita serrilhado em tela grande.

## Como rodar local
```
python .claude\serve-staging.py C:\APLICA~1\BONONI~4 5286
```
ou pelo `launch.json` (`bononi-hub`, porta 5286). Sobe apontando pro **banco de teste**, com a
faixa "BANCO DE TESTE" no rodapé. Como as contas do Auth do Hub só existem em produção, o login
local não passa — pra inspecionar o portal, renderize a casca pelo console:

```js
document.getElementById('login-wrap').classList.remove('show');
document.getElementById('auth-loading').style.display = 'none';
document.getElementById('portal').classList.add('show');
mostrarPortal({ nome: 'Fulano', admin: true, modulos: [] });
```

## Verificado
- Login, portal (11 cards), Integrador (5 subabas), Configuração (saúde + Umbler), modal de
  senha — desktop e 375px.
- `node --check` no bloco de script: OK. Zero erro de console vindo do front.
- Os `HTTP 404` que aparecem no Integrador/Configuração local são as tabelas `integ_*`/`vw_rep_*`
  que **não existem no banco de teste** — não têm relação com o visual.
- Nenhum hex ou rgba solto sobrou fora de `ds/bononi-ds.css`.
- **Diff do JavaScript auditado linha a linha** antes de publicar: 513 linhas alteradas, todas
  string de estilo, nome de ícone ou rótulo. Nenhuma query, RPC, condição, fluxo ou regra de
  acesso mudou. Foi essa auditoria que achou as duas armadilhas da seção 6.
- Banner de saúde e chips de situação conferidos com dados sintéticos (OK / ATRASO / ERRO),
  pra provar que os fundos voltaram: `#e6f4ec` / `#fdf3e3` / `#fdecec`, três tints distintos.

## Publicação
Publicado na `main` em 14/09/2026 (deploy Vercel automático) depois da auditoria acima.
Se algo parecer estranho em produção, o `git revert` do commit devolve o visual antigo inteiro
— a mudança é só de apresentação, não há estado de banco pra desfazer junto.
