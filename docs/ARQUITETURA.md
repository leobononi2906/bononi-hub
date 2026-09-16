# Bononi Hub — arquitetura e referência

> Referência completa do app. Escrita em 14/09/2026 lendo o `index.html` inteiro.
>
> **O que é estável mora aqui** (o que o app faz, como se estrutura, o que lê e escreve, as
> convenções). **O que muda toda semana mora no [`STATUS.md`](STATUS.md)** — pendências, dev-log,
> o que está quebrado agora. Se os dois divergirem, o `STATUS.md` ganha.

---

## 1. O que é

O Hub é o **porteiro do grupo**: a porta de entrada única dos apps internos do Grupo Bononi
Acessórios. Faz três coisas, nesta ordem de importância:

1. **Login unificado** (Supabase Auth) — uma conta serve todos os apps.
2. **Controle de acesso** — é aqui que se libera e se revoga quem entra em qual app.
3. **Centro de configuração** — cadastro de funcionários, saúde da replicação do ERP,
   classificação dos canais da Umbler e o painel do Integrador Bling→ERP.

O que ele **não** é: não tem lógica de negócio própria, não calcula nada, não é dono de dado
operacional. É porteiro e mesa de configuração.

---

## 2. Onde vive

| | |
|---|---|
| **Repositório** | https://github.com/leobononi2906/bononi-hub (branch `main`) |
| **Clone nesta máquina** | `C:\Aplicações da bononi\bononi-hub` |
| **Produção** | https://bononi-hub.vercel.app |
| **Deploy** | Vercel automático — **`push` na `main` é publicar** |
| **Banco** | Supabase `vishxwdxqiygbxmtpfoy` (sa-east-1), o projeto único do grupo |
| **Rodar local** | `launch.json` → `bononi-hub`, porta **5286** (ver §10) |

> ⚠️ O `STATUS.md` histórico citava `C:\CLAUDE\Projetos GitHub\...` — esse é o caminho da máquina
> do Leo. Nesta máquina (`ecommerce06`) o clone com git é o de cima.

### Dependências externas
Só três, todas por CDN, e nenhuma com build:

| O quê | De onde | Pra quê |
|---|---|---|
| `@supabase/supabase-js@2` | jsDelivr | Auth e client |
| Archivo · Barlow · IBM Plex Mono | Google Fonts | Tipografia do design system |
| `lucide-static@0.544.0` | unpkg | Ícones (via CSS mask) |

**Não há `package.json`, build, bundler nem framework.** É um `index.html` servido estático.
Isso é decisão, não descuido: o app é pequeno o bastante e a ausência de build significa que
qualquer pessoa abre o arquivo e entende, e que `push` = produção sem etapa intermediária.

### A chave anon exposta é por design
`SUPA_KEY` está em texto claro no `index.html`. Isso é correto para chave `anon` do Supabase —
ela é pública por definição. O que protege o dado é a autorização no banco, não o segredo da
chave. **Nunca** colocar `service_role` aqui: operação privilegiada vai por Edge Function (§6).

---

## 3. Anatomia do arquivo único

`index.html`, ~3.700 linhas, na ordem em que aparecem:

| Linhas | O que é |
|---|---|
| 1–17 | `<head>`: fontes, `ds/bononi-ds.css` |
| 18–608 | `<style>`: ponte de variáveis + camada de produto sobre o design system |
| 616–621 | Tela de carregamento (`#auth-loading`) |
| 622–648 | Tela de login (`#login-wrap`) |
| 649–703 | Topbar + saudação + grade de apps (`#portal`) |
| 704–730 | Painel **Usuários** (`#admin-panel`) |
| 731–801 | Painel **Configuração** (`#config-panel`) — saúde do sync + Umbler |
| 802–986 | Painel **Integrador** (`#integrador-panel`) — 5 subabas |
| 987–1069 | Modais de vincular NF e de editar/criar usuário |
| 1070–3550 | `<script>` — todo o comportamento |
| 3552–3703 | Modais de senha, funcionários, confirmação e toast |

Os painéis **não** são rotas: são `<div>` que alternam `display`. `toggleAdmin()`,
`toggleConfig()` e `toggleIntegrador()` fecham os outros dois antes de abrir o seu — é isso que
garante que nunca há dois painéis abertos ao mesmo tempo. Não há histórico de navegação: o botão
Voltar do navegador sai do Hub.

### Dentro do `<script>`

O arquivo é dividido por comentários de seção. **Navegue pela âncora, não pela linha** — a linha
envelhece a cada commit, o comentário não. Linhas conferidas em 14/09/2026.

| Linha | Âncora (grep) | Bloco |
|---|---|---|
| 1073 | `// ── Ícones` | `ic()`, `hydrateIcons()`, o `MutationObserver` |
| 1103 | `const APPS = [` | **Catálogo de apps** — a fonte da verdade do portal |
| ~1190 | `function renderApps` | Monta a grade, filtrando por `modulos` |
| ~1203 | `function mostrarPortal` | Entrada no portal; liga os timers de 5 min |
| ~1250 | `async function fazerLogin` | Login e logout |
| 1346 | `// ── ADMIN` | Toggles dos três painéis |
| 1452 | `async function _sbGet` | **`_sbGet` / `_sbWrite`** — os dois únicos caminhos de dado |
| 1474 | `═ INTEGRADOR ═` | Estado, subabas e KPIs do Integrador |
| 1532 | `// ── Pedidos` | Integrador → histórico das integrações |
| 1630 | `Automações → Transferência` | Integrador → rotas de transferência entre empresas |
| 1963 | `// ── Produtos & Kits` | Integrador → fila de pendências |
| 2165 | `// ── Faturas de frete` | Integrador → faturas e vínculo de CTe |
| 2404 | `// ── Seção 1: Saúde` | Configuração → saúde da replicação |
| 2467 | `// ── Seção 2: Canais` | Configuração → canais da Umbler |
| 2628 | `// ── Seção 2b: Usuários` | Configuração → de-para de atendente |
| ~2820 | `const _GRUPOS` | Usuários: agrupar, listar, editar, salvar |
| 3119 | `// ── Resetar Senha` | Reset pelo admin |
| 3175 | `// ── Minha Senha` | Troca da própria senha |
| 3212 | `// ── Funcionários` | CRUD de `rh_funcionarios` |
| 3388 | `// ── Deletar Usuário` | Exclusão via Edge |
| 3411 | `// ── Indicador de Sync` | O chip de status na topbar |
| 3503 | `function bononiConfirmar` | `bononiConfirmar` / `bononiToast` |
| 3533 | `async function init` | Ponto de entrada |

---

## 4. Modelo de acesso

Toda a autorização mora no **`user_metadata` do usuário no Supabase Auth**. Não há tabela de
perfis, não há RLS ligada hoje (ver `references/seguranca.md` no contexto geral).

```jsonc
{
  "nome": "Fulano de Tal",
  "admin": true,                          // admin GLOBAL: vê e administra tudo
  "modulos": ["financeiro", "compras"],   // apps que ESTE usuário acessa
  "admin_modulos": ["compras"]            // apps em que ele é admin daquele app
}
```

- **`modulos`** é a lista de chaves de acesso. `renderApps()` filtra o catálogo por ela.
- **`admin: true`** vê **todos** os apps do catálogo e ganha os 4 botões de administração.
- **`admin_modulos`** (desde 11/08/2026) marca admin **de um app específico**. Só faz sentido se
  a chave também estiver em `modulos` — o formulário força isso.
  ⚠️ **O enforcement é só centralizar aqui.** O Hub grava e mostra o dado; cada app passa a lê-lo
  quando for tocado. Hoje a maioria ainda não lê.

### ⚠️ A armadilha: chave de acesso ≠ nome do app
Em três casos o nome que a pessoa vê não é a chave que se grava:

| A pessoa vê | A chave é |
|---|---|
| Comercial Stonni | `stonni` |
| Consulta Vendas | `varejo` |
| CRM Atacado | `atacado` |

As 13 chaves concedíveis: `financeiro` · `compras` · `assistencia` · `cobranca` · `ecommerce` ·
`atacado` · `stonni` · `frete` · `loja` · `operacoes` · `expedicao` · `rede-autorizada` · `varejo`.

**Fonte da verdade são duas listas no `index.html`, e app novo tem de entrar nas DUAS:**
`APPS` (o cartão no portal) e `MODULOS_LABELS` (o checkbox no modal de acesso). Entrar só em uma
gera o bug silencioso: ou o app não aparece pra ninguém, ou não dá pra liberar o acesso a ele.

> ### ⚠️ Hoje as duas listas **não batem** (conferido em 14/09/2026)
> `MODULOS_LABELS` tem **13** chaves; `APPS` tem **11** cartões. Sobram duas chaves que dá pra
> conceder mas que **não têm cartão nenhum no portal**:
>
> | Chave órfã | App | Efeito |
> |---|---|---|
> | `atacado` | CRM Atacado | Marcar o acesso não faz aparecer nada pra pessoa |
> | `operacoes` | Operações | Idem |
>
> Quem recebe uma dessas entra no Hub e não vê o app — sem mensagem de erro, porque do ponto de
> vista do código está tudo certo: o módulo está no metadata, só não há cartão pra renderizar.
> **Não dá pra saber pelo código se isso é proposital** (app descontinuado, ou que se acessa por
> link direto) **ou lacuna.** Decidir e então: ou entra em `APPS`, ou sai de `MODULOS_LABELS`.

### Como usuários são agrupados na tela
`classificarUsuario()` separa em **Internos / Representantes / Rede Autorizada** por heurística,
nesta ordem (primeira que casar ganha):

1. `admin: true` → interno
2. tem algum módulo de back-office (`financeiro`, `compras`, `cobranca`, `ecommerce`, `loja`,
   `operacoes`, `expedicao`, `varejo_admin`) → interno
3. e-mail contém "bononi" → interno
4. tem `rede-autorizada` → autorizada
5. tem `stonni` → representante
6. sobrou → autorizada

É heurística de **apresentação**, não de permissão — errar o grupo não libera nada a mais. Mas
note o item 3: o e-mail participa da classificação, então um interno com e-mail pessoal cai no
grupo errado até ganhar um módulo de back-office.

---

## 5. As telas

### Login
E-mail e senha via `sb.auth.signInWithPassword`. A saudação ("Bom dia/tarde/noite") vem da hora
local. Erro de credencial é traduzido; qualquer outro erro aparece cru, de propósito.

### Portal
A grade de apps. Cartão sem `url` vira "Em breve" e fica desabilitado. Todo cartão abre em aba
nova (`target="_blank" rel="noopener"`). Quem não tem nenhum módulo vê "Nenhum aplicativo
disponível para seu perfil".

Na topbar: o **indicador de sync do ERP** (§7), o chip do usuário e, só pra admin, os 4 botões
de administração + Senha + Sair.

### Usuários (só admin)
Lista via RPC `admin_listar_usuarios`, agrupada em chips por tipo, com busca por nome e e-mail.
O modal de edição dá: nome, e-mail, admin global, e um checkbox por módulo — cada um com um
toggle **admin** ao lado, que só habilita se o acesso estiver marcado.

- **Criar** → Edge Function `admin-usuarios` (`acao: 'criar'`), que precisa de `service_role`.
- **Editar** → RPC `admin_atualizar_usuario`, que faz **merge** no metadata (desde 11/08 não
  sobrescreve mais o objeto inteiro — antes, salvar um usuário apagava chaves de outros apps).
- **Resetar senha** e **deletar** → Edge `admin-usuarios`.

O painel colapsável "Admins por aplicação" mostra os admins globais e, por app, quem é admin dele.

### Funcionários (só admin)
CRUD de `rh_funcionarios` — o cadastro central de pessoas do grupo, que outros apps consomem.
Filtros por departamento, status e busca. Lê com `Range: 0-9999` no **header** (não na query
string — ver §8).

### Configuração (só admin)
Duas seções:
- **Saúde da replicação** — banner de estado (OK/ATRASO/ERRO) de `vw_rep_saude` mais uma linha
  por objeto replicado de `vw_rep_status`.
- **Umbler**, em duas abas:
  - **Canais** — cada canal da Umbler aponta pra um segmento (atacado/varejo/assistência/
    financeiro/ecommerce/pendente). Salvar chama `umbler_classificar_canal`, que **re-carimba o
    histórico inteiro daquele canal no banco**, não só dali pra frente. Dá pra remover e
    restaurar canal da lista, e há uma aba "não vinculados" com canais que tiveram contato nos
    últimos 60 dias e não estão no de-para.
  - **Usuários** — de-para `id_membro_umbler` → pessoa do ERP (`rh_funcionarios`). Existe porque
    a Umbler manda o id do membro em toda mensagem mas **nunca manda o nome**; sem esse cadastro
    todo relatório por atendente fica anônimo. Contexto completo em
    [`2026-08-20-umbler-usuarios-e-analise-backend.md`](2026-08-20-umbler-usuarios-e-analise-backend.md)
    e [`UMBLER-FONTE-UNICA.md`](UMBLER-FONTE-UNICA.md).

### Integrador (só admin)
O painel do fluxo **Bling → ERP & Frete**, em 5 subabas:

| Subaba | O que faz |
|---|---|
| **Canais** | De-para canal do Bling → empresa, operação, vendedor, cond. pagto e centro de estoque. É o que o integrador usa ao gravar a venda. Tem também o plano de contas do financeiro por canal. |
| **Pedidos** | Histórico das integrações, com status `gravado` / `pronto` / `com_erro` / `recebido`. |
| **Produtos & Kits** | Fila de pendências: SKU do Bling sem produto no ERP, kit a compor, produto que existe no ERP mas não está cadastrado naquela empresa. Resolver aqui e clicar em "Reprocessar pedidos" destrava. |
| **Faturas de frete** | Cadastro de fatura da transportadora e vínculo dos CTe/NF que ela cobre, pra virar conta a pagar. |
| **Automações** | Rotas de transferência entre empresas: quando uma empresa vende sem estoque, a rota define de qual empresa sai e pra qual entra. **É só a configuração** — o robô que executa é etapa futura. |

> **Detalhe que confunde:** o vínculo de CTe descobre a empresa pelo **CNPJ do emitente dentro da
> chave da NFe** (posições 6–20), pelo mapa `INTEG_EMP_CNPJ`. Empresa nova do grupo precisa
> entrar nesse mapa, senão o CTe dela não aparece pra vincular.

---

## 6. Camada de dados — tudo que o Hub toca

### Lê (`SELECT`)

| Objeto | Onde | Observação |
|---|---|---|
| `vw_rep_saude`, `vw_rep_status` | Indicador de sync, Configuração | Saúde do replicador próprio |
| `rh_funcionarios` | Funcionários, de-para Umbler | Cadastro central de pessoas |
| `umbler_canais_resumo`, `vw_umbler_canais_nao_vinculados`, `vw_umbler_canal_alerta` | Config → Canais | |
| `vw_umbler_usuarios_resumo`, `vw_umbler_usuarios_nao_vinculados` | Config → Usuários | |
| `integ_config_canal`, `integ_pedido`, `integ_map_produto`, `vw_integ_skus_pendentes` | Integrador | |
| `integ_transferencia_rota`, `integ_transferencia_rota_produto` | Integrador → Automações | |
| `frt_faturas`, `frt_conhecimentos` | Integrador → Faturas | |
| `vw_fb_estoque_centro`, `vw_dim_vendedor`, `vw_fb_contatos`, `vw_fb_produtos_compras` | Selects do Integrador | **Espelho do Firebird — nunca escrever** |

### Escreve

| Objeto | Operação | Onde |
|---|---|---|
| `integ_config_canal` | upsert (`on_conflict=canal`) | Integrador → Canais |
| `integ_map_produto` | upsert (`origem,sku_externo`) | Integrador → Produtos |
| `geral_bling_composicoes` | upsert (`sku_bling`) | Integrador → Kits |
| `integ_transferencia_rota` | POST / PATCH / DELETE | Integrador → Automações |
| `integ_transferencia_rota_produto` | upsert / DELETE | Integrador → Automações |
| `frt_faturas` | upsert (`transportadora,num_fatura`) + PATCH | Integrador → Faturas |
| `frt_conhecimentos` | PATCH em lote (`id=in.(…)`) | Vínculo de CTe |
| `rh_funcionarios` | POST / PATCH | Funcionários. **Não há exclusão** — inativar é `PATCH {ativo:false}` |
| `auth.users.user_metadata` | via RPC / Edge | Usuários |

### RPCs
`admin_listar_usuarios` · `admin_atualizar_usuario` · `umbler_classificar_canal` ·
`umbler_set_canal_ativo` · `umbler_classificar_usuario` · `umbler_set_usuario_ativo` ·
`umbler_intake_saude`

### Edge Functions
| Função | Uso | Estado |
|---|---|---|
| `admin-usuarios` | criar / resetar senha / deletar usuário (precisa de `service_role`) | **Deploy-only, fora do repo.** E ainda **não grava `admin_modulos` na criação** — em usuário novo, definir o admin-por-app numa edição seguinte |
| `integ-montar-pedido` | "Reprocessar pedidos" do Integrador | Versionada em outro repo |
| `umbler-intake` | Webhook da Umbler | Versionada aqui em `supabase/functions/` |

> 📌 Edge Function **sobe pelo painel do Supabase** — não sai no deploy do site nem pelo CLI
> desta máquina.

---

## 7. Convenções de código do app

**Toda leitura e escrita passa por `_sbGet` / `_sbWrite`** (linhas 1451–1470). São `fetch()`
direto no PostgREST com o token da sessão. Se precisar de dado novo, use esses dois — não crie
um terceiro caminho.

```js
const linhas = await _sbGet('minha_tabela?select=*&order=criado_em.desc&limit=200');
await _sbWrite('minha_tabela?on_conflict=chave', 'POST', payload,
               'return=representation,resolution=merge-duplicates');
```

Regras que já custaram bug no grupo e valem aqui:

- **`Range` vai no header, nunca na query string.** O PostgREST corta em 1.000 linhas por padrão;
  `?limit=` grande não resolve sozinho. Ver `carregarFuncionarios()`.
- **Nada de `confirm()` / `alert()` nativos** — quebram no Safari do iOS. Use `bononiConfirmar()`
  (modal, retorna Promise) e `bononiToast()`.
- **Ícone é `ic()` ou `<i class="ic" data-ic="nome">`, nunca emoji.** Um `MutationObserver`
  hidrata sozinho o que entrar por `innerHTML` — não é preciso chamar `hydrateIcons()` à mão.
- **Token, nunca literal de cor.** O único lugar com hex é `ds/bononi-ds.css`.
- Os nomes velhos de variável (`--blue`, `--muted`, `--surface`…) continuam funcionando por uma
  ponte no `:root`, mas **código novo usa o token do design system direto**.

Design system completo: [`2026-09-14-design-system.md`](2026-09-14-design-system.md).

---

## 8. Runbooks

### Liberar ou revogar acesso
Usuários → achar a pessoa → Editar → marcar/desmarcar o módulo → Salvar. Revogar é desmarcar.
O efeito é imediato no próximo login (o metadata vem na sessão).

### Adicionar um app novo ao portal
1. Entrada em **`APPS`** (`id`, `nome`, `desc`, `icon` Lucide, `cor`, `acesso`, `url`).
2. Entrada em **`MODULOS_LABELS`** com a mesma chave de `acesso`. **As duas, sempre.**
3. Se for app de back-office (staff, não parceiro), acrescentar a chave em `_MODULOS_BACKOFFICE`
   pra classificação de grupo continuar certa.
4. `url: null` deixa o cartão como "Em breve".

### Publicar
`git push origin main`. A Vercel publica sozinha. Depois **confira o que está no ar** — push não
é deploy: o build pode falhar com tudo verde no git.

```bash
curl -sI https://bononi-hub.vercel.app | head -3
```

### Rodar local
```bash
python "C:\Users\ecommerce06\Desktop\Aplicações Bononi\.claude\serve-staging.py" C:\APLICA~1\BONONI~4 5286
```
Sobe apontando pro **banco de teste**, com faixa "BANCO DE TESTE" no rodapé.

⚠️ **O login local não passa**: contas do Auth são por projeto e as do Hub só existem em produção.
Pra inspecionar o portal sem logar, renderize a casca pelo console:

```js
document.getElementById('login-wrap').classList.remove('show');
document.getElementById('auth-loading').style.display = 'none';
document.getElementById('portal').classList.add('show');
mostrarPortal({ nome: 'Fulano', admin: true, modulos: [] });
```

Os `HTTP 404` no Integrador e na Configuração são as tabelas `integ_*` / `vw_rep_*` que não
existem no banco de teste. É esperado.

---

## 9. Armadilhas conhecidas

| Armadilha | Consequência |
|---|---|
| **Chave ≠ nome do app** em `stonni`, `varejo`, `atacado` | Liberar o módulo errado |
| **App novo só numa das duas listas** | Ou não aparece, ou não dá pra liberar |
| **`atacado` e `operacoes` só em `MODULOS_LABELS`** | Acesso concedível que não mostra cartão nenhum (§4) |
| **Edge `admin-usuarios` não grava `admin_modulos` na criação** | Usuário novo sai sem admin-por-app; corrigir editando depois |
| **`admin_modulos` quase não tem enforcement** | O Hub grava, mas a maioria dos apps ainda não lê |
| **`Range` na query string em vez do header** | Lista corta em 1.000 linhas, calada |
| **Empresa nova fora de `INTEG_EMP_CNPJ`** | CTe dela não aparece pra vincular à fatura |
| **Arquivo único de ~3.700 linhas** | Quebrar em pedaços aos poucos, ao mexer |
| **Sem rota nem histórico** | Botão Voltar do navegador sai do Hub |

### Código morto que parece vivo
- `verificarSync()` faz `ind.className = 'sync-ok' / 'sync-warn' / 'sync-error' / 'sync-skip'`,
  mas **essas quatro classes nunca tiveram CSS**. O indicador funciona porque a cor do ponto e o
  texto são aplicados inline. Ou se escreve o CSS (viraria um Badge do design system), ou se
  remove o `className`. Hoje é inofensivo, só confuso.
- `<div class="orb orb-1">` e `orb-2` são resto do tema escuro antigo. `.orb { display: none }`,
  então são markup inerte.

---

## 10. O que ainda falta

Lista viva no [`STATUS.md`](STATUS.md). Os itens estruturais:

1. **Decidir o destino de `atacado` e `operacoes`** — hoje são acesso concedível sem cartão (§4).
2. **Edge `admin-usuarios` aceitar `admin_modulos` na criação.**
3. **Cada app ler `admin_modulos`** pra liberar suas telas de admin — hoje o dado existe e quase
   ninguém consome.
4. **Quebrar o `index.html`** em pedaços, aos poucos, conforme se mexe.
5. **Fonte e ícones da marca** — Archivo/Barlow e Lucide são substitutos declarados do design
   system, à espera dos arquivos licenciados.

---

## 11. Documentos relacionados

| Documento | O que responde |
|---|---|
| [`STATUS.md`](STATUS.md) | Estado atual, pendências, dev-log |
| [`2026-09-14-design-system.md`](2026-09-14-design-system.md) | Como o design system foi aplicado, e as armadilhas do método |
| [`2026-09-16-hierarquias-de-acesso.md`](2026-09-16-hierarquias-de-acesso.md) | O módulo de hierarquias: fonte × espelho, as duas cadeiras de admin, e as travas |
| [`UMBLER-FONTE-UNICA.md`](UMBLER-FONTE-UNICA.md) | O projeto de intake único da Umbler |
| [`2026-08-20-umbler-usuarios-e-analise-backend.md`](2026-08-20-umbler-usuarios-e-analise-backend.md) | Camada canônica `umbler_msg` e o de-para de atendente |
| [`2026-08-25-umbler-intake-hardening.md`](2026-08-25-umbler-intake-hardening.md) | Endurecimento do webhook |
