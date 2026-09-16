# Hierarquias de acesso — módulo de usuários

> 16/09/2026 · Hub (definição) + cada app (leitura) · migration `0003_geral_hierarquias.sql`

## O que mudou, em uma frase

Antes, "quem acessa o quê" era uma lista de quadradinhos marcados à mão, pessoa por pessoa, sem
registro de quem marcou nem do porquê. Agora existe **hierarquia**: um papel com nome, com o que
ele faz escrito em linguagem de negócio, e uma matriz de módulo × ação. Atribuir a hierarquia a
alguém **recalcula o `user_metadata` daquela pessoa** — e é só isso que os outros apps leem.

## A decisão que faz isso ser implantável numa sessão

> **A hierarquia é a fonte; o `user_metadata` é espelho derivado.**

Não foi criado mecanismo novo de permissão. Os apps continuam fazendo exatamente o que já faziam:

```js
meta.admin === true || (meta.modulos || []).includes('compras')
```

Nenhum dos 11 apps do catálogo precisou ser reescrito. Se a hierarquia fosse um mecanismo
paralelo, **nenhum app passaria a obedecê-la** sem reescrita — e isso viraria projeto de
trimestre em vez de trabalho de um dia.

## O que ela é, e o que ela não é

**Isto organiza e registra. Não protege.** A chave `anon` está no fonte de todo app e a maioria
das tabelas não tem RLS: a hierarquia decide o que a pessoa **vê**, não o que a API **impede**.
Vira segurança de verdade quando o app bater no banco com o **JWT do usuário** e a tabela tiver
policy real — nessa ordem, nunca o contrário. O rodapé do painel de cada app diz isso em voz
alta, de propósito.

O que **já nasceu** seguro de verdade: as tabelas deste módulo. Ver §Enforcement.

## As duas cadeiras de admin

| Papel | No `user_metadata` | Vê a tela de hierarquias? |
|---|---|---|
| **Admin global** | `admin: true` | **Sim — e só ele** |
| **Admin de módulo** | `admin_modulos: ['compras', …]` | **Não.** Nem no menu |
| Usuário | `modulos: [...]` | Não |

**O admin de módulo fica de fora, e não é desconfiança.** Quem administra um módulo opera dentro
dele. Se pudesse editar hierarquia, poderia se promover, promover um colega, ou dar a alguém
acesso a um módulo que não é dele — e o registro diria que foi legítimo. É a mesma razão pela
qual quem aprova compra não é quem cadastra fornecedor.

O que o admin de módulo continua podendo: **ver** quem tem acesso ao módulo dele (§Módulo leitor).

## O achado que quase virou revogação silenciosa

O Hub tinha **três listas de módulos**, e elas já tinham divergido:

| Lista | Onde | Tinha |
|---|---|---|
| `APPS[].acesso` | catálogo de cartões | 11 chaves |
| `MODULOS_LABELS` | modal de usuário | 13 (a mais: `atacado`, `operacoes`) |
| `_MODULOS_BACKOFFICE` | classificação interno/externo | tinha **`varejo_admin`**, que não estava em nenhuma das outras |

`varejo_admin` é exatamente a chave que o `bononi-vendas` confere para liberar a visão de todos
os vendedores. Isso importa muito agora, e não importava antes: **a matriz da hierarquia grava
`modulos` por cima do que existia**. Qualquer chave que a matriz não conhecesse viraria acesso
**revogado em silêncio** na primeira vez que a pessoa recebesse uma hierarquia.

Consertado com um **registro único** (`MODULOS`, junto ao `APPS`): o que tem cartão herda o nome
do app; o que não tem entra em `MODULOS_EXTRAS` com o motivo escrito. `MODULOS_LABELS` passou a
ser derivado — não dá mais para as duas divergirem. São 14 chaves, e a matriz cobre as 14.

> Isso encerra a pendência de 14/09 ("decidir o destino de `atacado` e `operacoes`") pelo lado
> do risco: elas não somem mais da matriz. Continuam **sem cartão no `APPS`**, ou seja, quem
> recebe não vê nada no portal — a decisão de negócio segue em aberto, mas agora está escrita
> na própria tela.

## O que uma hierarquia define

1. **Nome e descrição** — o que ela faz, em linguagem de negócio. A RPC **recusa** salvar sem
   descrição: é o campo que evita a lista virar `perfil_1`, `perfil_2`.
2. **Módulos** — as 14 chaves do registro único.
3. **O que pode fazer em cada um** — `visualizar`, `incluir`, `editar`, `excluir`, `aprovar`,
   `exportar`. Vocabulário que o ERP já usa; verbo novo não foi inventado.
4. **Escopo** — empresas (vazio = todas). Sem escopo, "ver financeiro" é ver o do grupo inteiro.
5. **Admin do módulo** — um checkbox por linha, que vira `admin_modulos` no espelho.

O que a hierarquia **não** define: `admin: true`. Admin global se dá pessoa a pessoa, com
confirmação — nunca por herança de papel.

## Onde cada parte mora

| Parte | Onde | Quem |
|---|---|---|
| Definir hierarquia (criar/editar/arquivar) | **só no Hub** | só admin global |
| Atribuir hierarquia a pessoas | no Hub | só admin global |
| "Quem tem acesso aqui" (leitura) | **em cada app** | admin global e admin daquele módulo |

O CRUD fica num lugar só porque duplicá-lo em 11 apps seriam 11 telas para auditar e 11 lugares
para introduzir furo — a doença das telas gêmeas no pior lugar possível. Já aconteceu neste
grupo com OS e Financeiro, onde o porte perdeu `finally` em silêncio. Aqui o que se perderia
não é um `finally`: é uma trava.

## Enforcement — e por que estas tabelas já nascem fechadas

O esqueleto de partida expunha as tabelas com `select to authenticated using (true)`. **Não foi
seguido.** Aqui:

- **RLS ligada, ZERO policy** nas quatro tabelas, e `revoke all` para `anon` e `authenticated`.
- **Todo acesso passa por função `security definer`** que lê a identidade de `auth.uid()` —
  nunca de parâmetro que o front manda. É o Furo #2 do ERP (`_ator` vindo do cliente) não
  repetido: RPC que aceita "quem sou eu" como argumento não protege nada.

Isso também evita a armadilha conhecida — *"liguei RLS e a tela ficou vazia"*, que já zerou dado
em produção neste grupo. Aqui a tela nunca dependeu de ler a tabela direto, então não há ordem
de migração a respeitar.

## As travas, e o que cada uma evita

| Trava | Onde | O que evita |
|---|---|---|
| Só admin global escreve | RPC (JWT) | admin de módulo se promovendo |
| Ninguém edita a própria hierarquia | RPC + aviso na tela | o mesmo, um nível acima |
| Último admin global não sai | front | ninguém mais entra para consertar; o conserto vira chamado no suporte do Supabase |
| Hierarquia em uso arquiva, não apaga | RPC (sem `DELETE`) | gente com ponteiro morto |
| Salvar recalcula **todos** os afetados, na mesma transação | `geral_recalcular_hierarquia` | metade das pessoas com acesso antigo, sem ninguém perceber |
| **Quem não tem hierarquia não é tocado** | `geral_recalcular_espelho` | recalcular alguém do legado gravar `modulos: []` e trancar a pessoa fora de tudo |
| Escrita exige `ok:true` do banco | front | `UPDATE` barrado por RLS responde **200 e altera zero linhas** — "salvei a permissão" virando mentira silenciosa |
| Toda alteração vai para log | `geral_hierarquia_log` | não conseguir responder "quem liberou isso?" |

A penúltima é a mais traiçoeira desta casa: o PostgREST não erra quando a RLS barra, ele diz que
deu certo. Por isso cada RPC devolve `{ok:true}` explícito e o front confere.

O log é tabela própria. `app_logs` é log de **erro de JavaScript**, não trilha de auditoria.

## Convivência com o que já existia

`admin_atualizar_usuario` continua sendo quem grava nome e `admin` — e ela **mescla** o metadata
desde 11/08 (dev-log), então não apaga o que a hierarquia escreveu. Ainda assim, quando a pessoa
tem hierarquia o front manda o `modulos`/`admin_modulos` **calculados pela hierarquia**, não o
que está nos quadradinhos. Fica correto se a RPC mesclar e fica correto se um dia alguém a
mudar para substituir.

Na prática, no modal de usuário:

- **Com hierarquia** → os quadradinhos ficam visíveis mas travados, mostrando o que a hierarquia
  dá, com o texto explicando onde mudar.
- **Sem hierarquia** → comportamento de sempre, e a pessoa aparece na lista com a etiqueta
  tracejada **`manual`**.

A etiqueta `manual` é deliberada: é o que ainda falta migrar. Sumir da tela é como acesso legado
vira eterno.

## Módulo leitor (`ds/geral-acesso.js`)

Arquivo único, sem build, ~190 linhas, **cópia verbatim** em cada app — mesmo padrão já usado
com o `ds/bononi-ds.css`. Duas linhas para instalar:

```html
<script src="ds/geral-acesso.js?v=1"></script>
```
```js
GeralAcesso.montar({ alvo:'quem-tem-acesso', modulo:'compras', url:SUPA_URL, key:SUPA_KEY, sb });
```

Ele **não desenha nada** (e devolve `false`) quando: não há sessão, a RPC recusa (quem não pode
ver não vê nem a moldura), ou a migration ainda não está naquele banco. Silêncio é o
comportamento certo: painel de permissão meio carregado é pior que painel nenhum — e isso é o
que permite publicar o app **antes** da migration sem quebrar nada.

Instalado em **Compras** (Configurações → aba **Acessos**) como implementação de referência.

## Consertado de passagem

**`currentUser` nunca existiu.** Era usado em duas linhas do Hub e não estava declarado em lugar
nenhum — sob `'use strict'` isso é `ReferenceError`, e a troca da **própria senha** (modal "Minha
Senha") estava quebrada. Trocado por `_usuarioAtual`, variável que já existia no arquivo,
declarada e **nunca preenchida**; agora é preenchida no `mostrarPortal` com id, e-mail, nome,
admin e módulos. Achado porque o aviso de "não altera a própria hierarquia" precisava saber quem
está logado.

Também: o filtro de admin de módulo no `salvarUsuario` tinha `!cb.disabled`, que passou a
descartar o admin em silêncio assim que os quadradinhos ficam travados pela hierarquia. A
condição `modulos.includes(...)` ao lado já cobria o caso original.

## Como foi verificado

Front, na porta 5286/5287 contra o **banco de teste** (o `run-hub.cmd` já aponta para lá):

- Lista, editor e matriz das 14 chaves, com as notas dos três módulos sem cartão.
- Aviso "recalcula o acesso de N pessoas" antes de salvar.
- Payload do `geral_salvar_hierarquia` capturado: só módulos com `visualizar`, com os verbos.
- Modal de usuário: prévia travada com hierarquia, destravada sem; troca entre hierarquias
  repinta a prévia; volta para "manual" restaura o metadata real da pessoa.
- Ordem das chamadas ao salvar: `admin_atualizar_usuario` (com os módulos da hierarquia) →
  `geral_atribuir_hierarquia`.
- Trava do último admin global: **zero** chamadas saem, mensagem aparece.
- Trava da própria linha: select desabilitado, aviso em âmbar.
- Degradação sem a migration: mensagem explicando, app inteiro seguindo normal.
- Painel leitor renderizado com os quatro casos (com papel, admin do módulo, sem papel, admin
  global).
- `oxlint` com globais do navegador: **zero** `no-undef` no código novo.

Nada foi escrito em banco nenhum: as chamadas de escrita foram interceptadas no `fetch`.

### No banco de teste, com a migration aplicada

`0003` aplicada em `gxzhuewczlixksqrmjuk` em 16/09. Objetos conferidos: 4 tabelas, 15 funções,
RLS ligada nas 4, **zero policy** (é o desenho).

Com a **chave anon**, sem login — o teste que separa este módulo do resto do sistema:

| Tentativa | Resposta |
|---|---|
| `GET /geral_hierarquias` | **401** `permission denied for table` |
| `POST /rpc/geral_salvar_hierarquia` | **401** `permission denied for function` |
| `POST /rpc/geral_listar_hierarquias` | **401** `permission denied for function` |

Para comparar: um `GET` em `rh_funcionarios` com a chave anon do Hub, sem login nenhum,
responde **200**. Estas tabelas não.

Depois, **19 checagens** do ciclo completo com a identidade vindo do JWT simulado
(`supabase/testes/0003_hierarquias_ciclo.sql`, tudo em `BEGIN/ROLLBACK`) — 19/19:

| # | O que prova |
|---|---|
| 1–2 | admin global cria hierarquia |
| 3 | salvar **sem descrição** é recusado |
| 4–5 | atribuir recalcula o espelho na hora |
| 6 | atribuir **a si mesmo** é recusado |
| 7–7b | não-admin é `false`; admin de módulo é `true` no módulo dele |
| 8–9 | **admin de módulo não cria nem atribui hierarquia** — a regra central |
| 10–12 | o leitor mostra o módulo de quem administra, e recusa o resto |
| 13 | o "efetivo" marca as exceções do legado |
| 14–15 | arquivar recalcula quem a tinha |
| 16–17 | **quem não tem hierarquia não é tocado**, e o metadata do admin ficou intacto |
| 18 | log com ação, ator e alvo |

**A checagem nº 5 é a que vale ler.** O alvo começou com `modulos: ["compras","varejo_admin"]`
no metadata legado. Depois de receber uma hierarquia que dá `compras` e `expedicao`, ficou com
`["compras","expedicao"]` — **`varejo_admin` saiu**. Isso é o comportamento correto (a hierarquia
é a fonte), e é exatamente o motivo de o registro único importar: se `varejo_admin` não
estivesse na matriz, nenhum admin conseguiria concedê-la de volta, e toda atribuição a alguém
do varejo revogaria o acesso dele em silêncio.

Depois do `rollback`: 0 hierarquias, 0 atribuições, 0 linhas de log, o usuário sintético sumiu e
o metadata do admin do banco de teste continua byte a byte o mesmo.

## O que NÃO foi feito

- **A migration não foi aplicada em PRODUÇÃO.** Só no banco de teste. O arquivo está em
  `supabase/migrations/0003_geral_hierarquias.sql`; o teste do ciclo, em
  `supabase/testes/0003_hierarquias_ciclo.sql`, vale rodar contra produção depois de aplicar.
- **Nenhuma hierarquia foi desenhada.** Papel bom nasce do trabalho, não do organograma — a
  pergunta que destrava é *"quem faz esse trabalho hoje, e o que essa pessoa precisa conseguir
  fazer?"*, e ela é para quem manda no processo, não para quem escreve o código.
- **Ninguém foi migrado.** O metadata legado continua valendo; a etiqueta `manual` mostra quem
  falta.
- **O leitor só está no Compras.** Faltam os outros 10 apps do catálogo — é cópia do arquivo +
  duas linhas em cada, mas é edição em 10 repos.
- **`geral_efetivo_usuario`** (o "efetivo" resolvido, com as exceções do legado marcadas) existe
  no banco e ainda não tem tela.
