# `supabase/testes/`

Scripts que conferem o módulo de hierarquias contra um banco de verdade.

**A diferença que importa antes de rodar qualquer um deles:**

| Arquivo | Persiste? | Onde pode rodar |
|---|---|---|
| `0003_hierarquias_ciclo.sql` | **Não** — `BEGIN/ROLLBACK` | qualquer banco |
| `0003_grants_authenticated.sql` | **Não** — `BEGIN/ROLLBACK` | qualquer banco |
| `SO-TESTE-liberar-propria-hierarquia.sql` | **SIM — altera função** | **só o banco de teste** |

Os dois primeiros desfazem tudo, inclusive o usuário sintético que criam. O terceiro **não**:
ele reescreve duas RPCs e a alteração fica. Por isso o prefixo `SO-TESTE-`.

---

## `0003_hierarquias_ciclo.sql` — 19 checagens

O ciclo inteiro: admin global × admin de módulo × não-admin, as travas, o espelho e o log.
Identidade vem de `request.jwt.claims`, que é como o PostgREST faz.

**O que ele NÃO cobre:** roda como o papel do CLI, que é superusuário — e superusuário passa por
cima de `grant`. Ele prova a **lógica**, não a permissão. Para isso existe o de baixo.

## `0003_grants_authenticated.sql` — 6 checagens

Faz `set local role authenticated` e só então chama as funções. É o único que prova o `grant`.

Sem ele, um `revoke all` sem o `grant execute to authenticated` correspondente daria **19/19 no
ciclo e uma tela morta** para o admin de verdade, com 401 em tudo: teste verde e app quebrado ao
mesmo tempo.

## `SO-TESTE-liberar-propria-hierarquia.sql` — ⚠️ altera o banco

Libera o admin global a atribuir hierarquia **a si mesmo**, removendo uma das travas boas.

**Por que existe:** o banco de teste tem **um usuário só**. Com um usuário, o ciclo (criar papel
→ atribuir → ver o espelho recalcular → abrir o app) é impossível de exercitar à mão no
navegador, porque a trava impede a auto-atribuição.

**O que o protege:** uma guarda no topo que recusa banco com mais de 5 usuários — e **ela aborta
o arquivo inteiro**, não só avisa. Conferido em 16/09/2026 contra produção (52 usuários) com um
arquivo isca de mesma forma: a guarda disparou e a função isca **não** foi criada. Rodar isso em
produção por engano dá erro e não aplica nada.

**Como desfazer** (e é o que produção tem, sempre):

```bash
npx supabase@2.117.0 db query --linked --project-ref <ref> \
  -f supabase/migrations/0003_geral_hierarquias.sql
```

Reaplicar a migration restaura as duas funções. Depois, rode o ciclo: a checagem **nº 6**
(`atribuir a si mesmo → RECUSA`) é exatamente a que volta a passar.

A linha `SO-TESTE` que ele grava em `geral_hierarquia_log` **fica** depois do restauro, de
propósito: é o rastro de que aquele banco já teve o bypass. Apagar registro de auditoria para
deixar o log bonito é o instinto errado.

---

## Como rodar

```bash
npx supabase@2.117.0 db query --linked --project-ref <ref> -f supabase/testes/<arquivo>.sql
```

Duas armadilhas do CLI, as duas silenciosas:

1. **Só mostra o resultado do ÚLTIMO comando do arquivo.** Um script com 14 `select` imprime 1.
   Por isso os testes acumulam tudo numa `temp table` e terminam com um `select` só.
2. **`raise notice` não aparece em lugar nenhum.**

Refs: produção `vishxwdxqiygbxmtpfoy` · teste `gxzhuewczlixksqrmjuk`.
