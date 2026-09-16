-- =====================================================================
-- 0003 — Hierarquias de acesso (módulo de usuários)
-- =====================================================================
-- Prefixo `geral_` porque é multi-app.
--
-- DESENHO EM UMA FRASE:
--   A hierarquia é a FONTE; o `user_metadata` é ESPELHO derivado. Os apps
--   continuam lendo `meta.modulos` / `meta.admin_modulos` como sempre —
--   nenhum app precisa ser reescrito.
--
-- DIFERENÇA PARA O ESQUELETO DA SKILL, e por quê:
--   1. Nenhuma tabela é exposta direto ao PostgREST. RLS ligada SEM policy
--      nenhuma + tudo por função `security definer` que lê `auth.uid()`.
--      Assim o módulo já nasce seguro, sem depender de o app migrar para
--      JWT primeiro — e sem o risco de "liguei RLS e a tela ficou vazia",
--      que já zerou dado em produção neste grupo.
--   2. `geral_recalcular_espelho` NÃO mexe em quem não tem hierarquia.
--      Sem essa trava, recalcular alguém do legado apaga o acesso dele.
--   3. Log próprio (`geral_hierarquia_log`). `app_logs` é log de ERRO de
--      JavaScript, não trilha de auditoria — não serve para "quem liberou".
--
-- ORDEM DE LEITURA: tabelas -> identidade -> espelho -> escrita -> leitura.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tabelas
-- ---------------------------------------------------------------------

create table if not exists geral_hierarquias (
  id            bigserial primary key,
  nome          text not null unique,
  -- O QUE ELA FAZ, em linguagem de negócio. É o campo que evita a lista
  -- virar perfil_1/perfil_2 e ninguém saber a quem dar.
  descricao     text not null,
  -- Escopo: sem isto, "ver financeiro" é ver o do grupo inteiro.
  empresas      int[]  not null default '{}',   -- vazio = todas
  parceiro_id   bigint,                         -- só rede autorizada
  arquivada     boolean not null default false, -- nunca DELETE: gente aponta pra cá
  criada_em     timestamptz not null default now(),
  criada_por    uuid,
  alterada_em   timestamptz,
  alterada_por  uuid
);

comment on table geral_hierarquias is
  'Papéis de acesso do grupo. Fonte da verdade; user_metadata é espelho derivado.';

-- Uma linha por módulo que a hierarquia alcança, com o que pode fazer nele.
-- Vocabulário igual ao que o ERP já usa — não invente verbo novo.
create table if not exists geral_hierarquia_modulos (
  hierarquia_id bigint not null references geral_hierarquias(id) on delete cascade,
  modulo        text   not null,              -- chave `acesso` do APPS do Hub
  visualizar    boolean not null default true,
  incluir       boolean not null default false,
  editar        boolean not null default false,
  excluir       boolean not null default false,
  aprovar       boolean not null default false,
  exportar      boolean not null default false,
  admin_modulo  boolean not null default false, -- vira admin_modulos no espelho
  primary key (hierarquia_id, modulo)
);

comment on column geral_hierarquia_modulos.modulo is
  'Chave `acesso` do registro APPS do Hub (financeiro, compras, varejo_admin...). NAO e o `id` do app: em varios eles diferem (com-stonni -> stonni, vendas -> varejo).';

-- Quem tem qual hierarquia. Uma por pessoa: duas hierarquias somando
-- permissão é onde ninguém mais consegue responder "por que ele vê isso?".
create table if not exists geral_usuario_hierarquia (
  user_id       uuid primary key,             -- auth.users.id
  hierarquia_id bigint not null references geral_hierarquias(id),
  atribuida_em  timestamptz not null default now(),
  atribuida_por uuid
);

create index if not exists ix_geral_uh_hierarquia
  on geral_usuario_hierarquia (hierarquia_id);

-- Controle de acesso sem histórico não responde a pergunta que sempre vem
-- depois: "quem liberou isso pro fulano?".
create table if not exists geral_hierarquia_log (
  id            bigserial primary key,
  quando        timestamptz not null default now(),
  quem          uuid,                 -- auth.uid() de quem fez
  quem_email    text,                 -- desnormalizado: o usuário pode ser apagado depois
  acao          text not null,        -- CRIAR | EDITAR | ARQUIVAR | ATRIBUIR | REMOVER
  hierarquia_id bigint,
  alvo_user     uuid,                 -- quando a ação é sobre uma pessoa
  alvo_email    text,
  antes         jsonb,
  depois        jsonb
);

create index if not exists ix_geral_hier_log_quando on geral_hierarquia_log (quando desc);

-- ---------------------------------------------------------------------
-- 2. Identidade — a partir do JWT, NUNCA de parâmetro do front
-- ---------------------------------------------------------------------
-- É aqui que o Furo #2 do ERP não se repete: RPC que aceita "quem sou eu"
-- como argumento não protege nada — qualquer um chama dizendo ser admin.

create or replace function geral_eh_admin_global()
returns boolean
language sql stable security definer set search_path = public as $fn$
  select coalesce(
    (select (raw_user_meta_data ->> 'admin')::boolean
       from auth.users where id = auth.uid()),
    false)
$fn$;

-- `@>` em vez do operador `?` de propósito: `?` é marcador de parâmetro em
-- vários clientes e a função quebra dependendo de quem chama.
create or replace function geral_eh_admin_do_modulo(p_modulo text)
returns boolean
language sql stable security definer set search_path = public as $fn$
  select coalesce(
    (select coalesce(raw_user_meta_data -> 'admin_modulos', '[]'::jsonb) @> to_jsonb(p_modulo)
       from auth.users where id = auth.uid()),
    false)
$fn$;

-- Quantos admins globais existem. O front usa para não deixar o último sair.
create or replace function geral_contar_admins_globais()
returns integer
language sql stable security definer set search_path = public as $fn$
  select count(*)::int from auth.users
   where coalesce((raw_user_meta_data ->> 'admin')::boolean, false)
$fn$;

-- ---------------------------------------------------------------------
-- 3. Log
-- ---------------------------------------------------------------------

create or replace function geral_log(
  p_acao text, p_hier bigint, p_alvo uuid, p_antes jsonb, p_depois jsonb)
returns void
language plpgsql security definer set search_path = public as $fn$
begin
  insert into geral_hierarquia_log (quem, quem_email, acao, hierarquia_id, alvo_user, alvo_email, antes, depois)
  values (auth.uid(),
          (select email from auth.users where id = auth.uid()),
          p_acao, p_hier, p_alvo,
          (select email from auth.users where id = p_alvo),
          p_antes, p_depois);
end $fn$;

-- ---------------------------------------------------------------------
-- 4. O espelho: hierarquia -> user_metadata
-- ---------------------------------------------------------------------
-- Os apps já leem meta.modulos / meta.admin_modulos. Recalcular o espelho
-- é o que faz a hierarquia valer sem reescrever app nenhum.
--
-- `admin: true` NÃO entra aqui de propósito: admin global se dá pessoa a
-- pessoa, com confirmação, nunca por herança de papel.
--
-- TRAVA QUE O ESQUELETO NÃO TEM: quem não tem hierarquia não é tocado.
-- Sem isto, recalcular alguém do legado grava `modulos: []` e tranca a
-- pessoa fora de tudo, sem erro nenhum.

create or replace function geral_recalcular_espelho(p_user uuid)
returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare
  v_mod  text[];
  v_adm  text[];
begin
  if not exists (select 1 from geral_usuario_hierarquia where user_id = p_user) then
    return jsonb_build_object('ok', false, 'motivo', 'sem hierarquia - metadata preservado');
  end if;

  select coalesce(array_agg(distinct hm.modulo) filter (where hm.visualizar), '{}'),
         coalesce(array_agg(distinct hm.modulo) filter (where hm.admin_modulo), '{}')
    into v_mod, v_adm
  from geral_usuario_hierarquia uh
  join geral_hierarquias h         on h.id = uh.hierarquia_id and not h.arquivada
  join geral_hierarquia_modulos hm on hm.hierarquia_id = h.id
  where uh.user_id = p_user;

  -- `||` mescla: preserva nome, admin e o resto do metadata. Substituir o
  -- objeto inteiro aqui apagaria o `admin` da pessoa.
  update auth.users
     set raw_user_meta_data =
         coalesce(raw_user_meta_data, '{}'::jsonb)
         || jsonb_build_object('modulos', to_jsonb(coalesce(v_mod, '{}'::text[])),
                               'admin_modulos', to_jsonb(coalesce(v_adm, '{}'::text[])))
   where id = p_user;

  return jsonb_build_object('ok', true,
                            'modulos', to_jsonb(coalesce(v_mod, '{}'::text[])),
                            'admin_modulos', to_jsonb(coalesce(v_adm, '{}'::text[])));
end $fn$;

-- Editar uma hierarquia mexe em TODO MUNDO que a tem. Recalcular pela
-- metade deixa parte das pessoas com acesso antigo e ninguém percebe —
-- por isso é um laço só, numa transação só.
create or replace function geral_recalcular_hierarquia(p_hier bigint)
returns integer
language plpgsql security definer set search_path = public as $fn$
declare v_n integer := 0; r record;
begin
  for r in select user_id from geral_usuario_hierarquia where hierarquia_id = p_hier loop
    perform geral_recalcular_espelho(r.user_id);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $fn$;

-- ---------------------------------------------------------------------
-- 5. Escrita — só admin global, conferido pelo JWT
-- ---------------------------------------------------------------------
-- O admin de MÓDULO não entra em nenhuma destas. É a regra central do
-- módulo: quem opera dentro de um módulo não define quem entra nele,
-- senão pode se promover e o registro diria que foi legítimo.

-- p_modulos: [{"modulo":"compras","visualizar":true,"incluir":true,...,"admin_modulo":false}, ...]
create or replace function geral_salvar_hierarquia(
  p_id          bigint,          -- null = criar
  p_nome        text,
  p_descricao   text,
  p_empresas    int[],
  p_parceiro_id bigint,
  p_modulos     jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare
  v_id     bigint := p_id;
  v_antes  jsonb;
  v_n      integer := 0;
  v_acao   text;
begin
  if not geral_eh_admin_global() then
    raise exception 'apenas o admin global pode definir hierarquia';
  end if;
  if coalesce(trim(p_nome), '') = '' then
    raise exception 'a hierarquia precisa de nome';
  end if;
  -- Sem descrição a lista vira perfil_1/perfil_2 e ninguém sabe a quem dar.
  if coalesce(trim(p_descricao), '') = '' then
    raise exception 'descreva o que essa hierarquia faz, em linguagem de negocio';
  end if;

  if v_id is null then
    insert into geral_hierarquias (nome, descricao, empresas, parceiro_id, criada_por)
    values (trim(p_nome), trim(p_descricao), coalesce(p_empresas, '{}'), p_parceiro_id, auth.uid())
    returning id into v_id;
    v_acao := 'CRIAR';
  else
    select to_jsonb(h) into v_antes from geral_hierarquias h where h.id = v_id;
    if v_antes is null then raise exception 'hierarquia % nao existe', v_id; end if;

    update geral_hierarquias
       set nome = trim(p_nome), descricao = trim(p_descricao),
           empresas = coalesce(p_empresas, '{}'), parceiro_id = p_parceiro_id,
           alterada_em = now(), alterada_por = auth.uid()
     where id = v_id;
    v_acao := 'EDITAR';
  end if;

  delete from geral_hierarquia_modulos where hierarquia_id = v_id;
  insert into geral_hierarquia_modulos
    (hierarquia_id, modulo, visualizar, incluir, editar, excluir, aprovar, exportar, admin_modulo)
  select v_id,
         m ->> 'modulo',
         coalesce((m ->> 'visualizar')::boolean, true),
         coalesce((m ->> 'incluir')::boolean, false),
         coalesce((m ->> 'editar')::boolean, false),
         coalesce((m ->> 'excluir')::boolean, false),
         coalesce((m ->> 'aprovar')::boolean, false),
         coalesce((m ->> 'exportar')::boolean, false),
         coalesce((m ->> 'admin_modulo')::boolean, false)
    from jsonb_array_elements(coalesce(p_modulos, '[]'::jsonb)) m
   where coalesce(m ->> 'modulo', '') <> '';

  -- Recalcula TODO MUNDO que tem esta hierarquia, na mesma transação.
  v_n := geral_recalcular_hierarquia(v_id);

  perform geral_log(v_acao, v_id, null, v_antes,
    jsonb_build_object('nome', trim(p_nome), 'descricao', trim(p_descricao),
                       'empresas', to_jsonb(coalesce(p_empresas, '{}')),
                       'modulos', coalesce(p_modulos, '[]'::jsonb)));

  return jsonb_build_object('ok', true, 'id', v_id, 'afetados', v_n);
end $fn$;

-- Hierarquia em uso não se apaga — arquiva. Apagar deixa gente com
-- ponteiro morto e o recálculo do espelho não sabe o que fazer.
create or replace function geral_arquivar_hierarquia(p_id bigint, p_arquivar boolean)
returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare v_n integer;
begin
  if not geral_eh_admin_global() then
    raise exception 'apenas o admin global pode arquivar hierarquia';
  end if;

  update geral_hierarquias
     set arquivada = coalesce(p_arquivar, true), alterada_em = now(), alterada_por = auth.uid()
   where id = p_id;
  if not found then raise exception 'hierarquia % nao existe', p_id; end if;

  -- Arquivar tira o acesso de quem a tem: o espelho passa a somar zero
  -- módulos. Isso é intencional, e por isso o front avisa quantos são antes.
  v_n := geral_recalcular_hierarquia(p_id);
  perform geral_log(case when coalesce(p_arquivar, true) then 'ARQUIVAR' else 'REATIVAR' end,
                    p_id, null, null, jsonb_build_object('afetados', v_n));

  return jsonb_build_object('ok', true, 'id', p_id, 'afetados', v_n);
end $fn$;

create or replace function geral_atribuir_hierarquia(p_user uuid, p_hier bigint)
returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare v_antes jsonb; v_esp jsonb;
begin
  if not geral_eh_admin_global() then
    raise exception 'apenas o admin global pode atribuir hierarquia';
  end if;

  -- Ninguém edita a própria hierarquia, nem o admin global. Separar quem
  -- opera de quem define poder é o que faz o controle valer alguma coisa.
  if p_user = auth.uid() then
    raise exception 'nao e possivel alterar a propria hierarquia';
  end if;

  if not exists (select 1 from geral_hierarquias where id = p_hier and not arquivada) then
    raise exception 'hierarquia % nao existe ou esta arquivada', p_hier;
  end if;

  select to_jsonb(uh) into v_antes from geral_usuario_hierarquia uh where uh.user_id = p_user;

  insert into geral_usuario_hierarquia (user_id, hierarquia_id, atribuida_por)
  values (p_user, p_hier, auth.uid())
  on conflict (user_id) do update
    set hierarquia_id = excluded.hierarquia_id,
        atribuida_em  = now(),
        atribuida_por = auth.uid();

  v_esp := geral_recalcular_espelho(p_user);
  perform geral_log('ATRIBUIR', p_hier, p_user, v_antes,
                    jsonb_build_object('hierarquia_id', p_hier, 'espelho', v_esp));

  return jsonb_build_object('ok', true, 'user_id', p_user, 'hierarquia_id', p_hier, 'espelho', v_esp);
end $fn$;

-- Tira a hierarquia e devolve a pessoa ao controle manual. O metadata fica
-- como está: zerar aqui trancaria a pessoa fora de tudo sem ninguém pedir.
create or replace function geral_remover_hierarquia(p_user uuid)
returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare v_antes jsonb;
begin
  if not geral_eh_admin_global() then
    raise exception 'apenas o admin global pode remover hierarquia';
  end if;
  if p_user = auth.uid() then
    raise exception 'nao e possivel alterar a propria hierarquia';
  end if;

  select to_jsonb(uh) into v_antes from geral_usuario_hierarquia uh where uh.user_id = p_user;
  delete from geral_usuario_hierarquia where user_id = p_user;
  perform geral_log('REMOVER', null, p_user, v_antes, null);

  return jsonb_build_object('ok', true, 'user_id', p_user, 'removida', v_antes is not null);
end $fn$;

-- ---------------------------------------------------------------------
-- 6. Leitura
-- ---------------------------------------------------------------------

-- Lista de hierarquias com os módulos e quantas pessoas usam.
-- Aberta a qualquer pessoa logada: a tela "quem tem acesso aqui" de cada
-- app depende dela. Por isso NADA de dado sensível nessas tabelas.
create or replace function geral_listar_hierarquias(p_incluir_arquivadas boolean default false)
returns jsonb
language sql stable security definer set search_path = public as $fn$
  select coalesce(jsonb_agg(x order by x ->> 'nome'), '[]'::jsonb) from (
    select jsonb_build_object(
             'id', h.id, 'nome', h.nome, 'descricao', h.descricao,
             'empresas', to_jsonb(h.empresas), 'parceiro_id', h.parceiro_id,
             'arquivada', h.arquivada,
             'pessoas', (select count(*) from geral_usuario_hierarquia uh where uh.hierarquia_id = h.id),
             'modulos', (select coalesce(jsonb_agg(to_jsonb(hm) - 'hierarquia_id' order by hm.modulo), '[]'::jsonb)
                           from geral_hierarquia_modulos hm where hm.hierarquia_id = h.id)
           ) as x
      from geral_hierarquias h
     where coalesce(p_incluir_arquivadas, false) or not h.arquivada
  ) t
$fn$;

-- Quem tem qual hierarquia. O front cruza com admin_listar_usuarios pelo id.
create or replace function geral_listar_atribuicoes()
returns jsonb
language sql stable security definer set search_path = public as $fn$
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', uh.user_id, 'hierarquia_id', uh.hierarquia_id,
           'hierarquia', h.nome, 'arquivada', h.arquivada,
           'atribuida_em', uh.atribuida_em,
           'atribuida_por', (select email from auth.users u where u.id = uh.atribuida_por)
         )), '[]'::jsonb)
    from geral_usuario_hierarquia uh
    join geral_hierarquias h on h.id = uh.hierarquia_id
$fn$;

-- O módulo LEITOR que vai em cada app: quem tem acesso AQUI, com a
-- hierarquia de cada um e o que ela permite. Só leitura — quem pode mudar
-- vai ao Hub. Admin global e admin DAQUELE módulo enxergam; mais ninguém.
create or replace function geral_quem_tem_acesso(p_modulo text)
returns jsonb
language sql stable security definer set search_path = public as $fn$
  select case
    when not (geral_eh_admin_global() or geral_eh_admin_do_modulo(p_modulo))
      then jsonb_build_object('erro', 'sem permissao')
    else jsonb_build_object(
      'modulo', p_modulo,
      'pessoas', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'user_id', u.id,
                 'nome',  u.raw_user_meta_data ->> 'nome',
                 'email', u.email,
                 'admin_global', coalesce((u.raw_user_meta_data ->> 'admin')::boolean, false),
                 'admin_modulo', coalesce(u.raw_user_meta_data -> 'admin_modulos', '[]'::jsonb) @> to_jsonb(p_modulo),
                 'ultimo_acesso', u.last_sign_in_at,
                 'hierarquia', h.nome,
                 'hierarquia_descricao', h.descricao,
                 'permissoes', to_jsonb(hm) - 'hierarquia_id' - 'modulo'
               ) order by u.raw_user_meta_data ->> 'nome')
          from auth.users u
          left join geral_usuario_hierarquia uh on uh.user_id = u.id
          left join geral_hierarquias h         on h.id = uh.hierarquia_id
          left join geral_hierarquia_modulos hm on hm.hierarquia_id = h.id and hm.modulo = p_modulo
         where coalesce((u.raw_user_meta_data ->> 'admin')::boolean, false)
            or coalesce(u.raw_user_meta_data -> 'modulos', '[]'::jsonb) @> to_jsonb(p_modulo)
      ), '[]'::jsonb))
  end
$fn$;

-- O "efetivo" de uma pessoa: o que ela consegue fazer, resolvido, e o que
-- o metadata tem que a hierarquia NÃO explica. Essa exceção precisa
-- aparecer marcada — sumir do relatório é como o acesso legado vira eterno.
create or replace function geral_efetivo_usuario(p_user uuid)
returns jsonb
language sql stable security definer set search_path = public as $fn$
  select case
    when not geral_eh_admin_global() then jsonb_build_object('erro', 'sem permissao')
    else (
      select jsonb_build_object(
        'user_id', u.id, 'email', u.email,
        'nome', u.raw_user_meta_data ->> 'nome',
        'admin_global', coalesce((u.raw_user_meta_data ->> 'admin')::boolean, false),
        'hierarquia', h.nome,
        'hierarquia_id', h.id,
        'modulos_metadata', coalesce(u.raw_user_meta_data -> 'modulos', '[]'::jsonb),
        'modulos_hierarquia', coalesce((
            select jsonb_agg(hm.modulo order by hm.modulo) from geral_hierarquia_modulos hm
             where hm.hierarquia_id = h.id and hm.visualizar), '[]'::jsonb),
        -- módulo que a pessoa tem e a hierarquia não dá = exceção (legado)
        'excecoes', coalesce((
            select jsonb_agg(m) from jsonb_array_elements_text(
                     coalesce(u.raw_user_meta_data -> 'modulos', '[]'::jsonb)) m
             where h.id is null
                or not exists (select 1 from geral_hierarquia_modulos hm
                                where hm.hierarquia_id = h.id and hm.modulo = m and hm.visualizar)
          ), '[]'::jsonb)
      )
      from auth.users u
      left join geral_usuario_hierarquia uh on uh.user_id = u.id
      left join geral_hierarquias h         on h.id = uh.hierarquia_id
     where u.id = p_user)
  end
$fn$;

create or replace function geral_log_recente(p_limite int default 50)
returns jsonb
language sql stable security definer set search_path = public as $fn$
  select case when not geral_eh_admin_global() then jsonb_build_object('erro', 'sem permissao')
    else coalesce((select jsonb_agg(to_jsonb(l) order by l.quando desc)
                     from (select * from geral_hierarquia_log
                            order by quando desc limit least(coalesce(p_limite, 50), 200)) l), '[]'::jsonb)
  end
$fn$;

-- ---------------------------------------------------------------------
-- 7. Fechar as tabelas: RLS ligada, ZERO policy
-- ---------------------------------------------------------------------
-- Com RLS ligada e nenhuma policy, `anon` e `authenticated` não leem nem
-- escrevem NADA direto pelo PostgREST. O único caminho são as funções
-- acima, que são `security definer` e conferem a identidade pelo
-- `auth.uid()` — não por parâmetro que o front manda.
--
-- Isso evita a armadilha conhecida ("liguei RLS e a tela ficou vazia"):
-- aqui a tela nunca dependeu de ler a tabela direto.

alter table geral_hierarquias        enable row level security;
alter table geral_hierarquia_modulos enable row level security;
alter table geral_usuario_hierarquia enable row level security;
alter table geral_hierarquia_log     enable row level security;

revoke all on table geral_hierarquias        from anon, authenticated;
revoke all on table geral_hierarquia_modulos from anon, authenticated;
revoke all on table geral_usuario_hierarquia from anon, authenticated;
revoke all on table geral_hierarquia_log     from anon, authenticated;

-- Escrita: só para quem está logado. `anon` não executa nenhuma delas.
revoke all on function geral_salvar_hierarquia(bigint, text, text, int[], bigint, jsonb) from public, anon;
revoke all on function geral_arquivar_hierarquia(bigint, boolean)                        from public, anon;
revoke all on function geral_atribuir_hierarquia(uuid, bigint)                           from public, anon;
revoke all on function geral_remover_hierarquia(uuid)                                    from public, anon;
revoke all on function geral_recalcular_espelho(uuid)                                    from public, anon;
revoke all on function geral_recalcular_hierarquia(bigint)                               from public, anon;
revoke all on function geral_log(text, bigint, uuid, jsonb, jsonb)                       from public, anon;

grant execute on function geral_salvar_hierarquia(bigint, text, text, int[], bigint, jsonb) to authenticated;
grant execute on function geral_arquivar_hierarquia(bigint, boolean)                        to authenticated;
grant execute on function geral_atribuir_hierarquia(uuid, bigint)                           to authenticated;
grant execute on function geral_remover_hierarquia(uuid)                                    to authenticated;

-- Leitura: idem — logado, e cada função já filtra o que pode mostrar.
revoke all on function geral_listar_hierarquias(boolean) from public, anon;
revoke all on function geral_listar_atribuicoes()        from public, anon;
revoke all on function geral_quem_tem_acesso(text)       from public, anon;
revoke all on function geral_efetivo_usuario(uuid)       from public, anon;
revoke all on function geral_log_recente(int)            from public, anon;
revoke all on function geral_contar_admins_globais()     from public, anon;
revoke all on function geral_eh_admin_global()           from public, anon;
revoke all on function geral_eh_admin_do_modulo(text)    from public, anon;

grant execute on function geral_listar_hierarquias(boolean) to authenticated;
grant execute on function geral_listar_atribuicoes()        to authenticated;
grant execute on function geral_quem_tem_acesso(text)       to authenticated;
grant execute on function geral_efetivo_usuario(uuid)       to authenticated;
grant execute on function geral_log_recente(int)            to authenticated;
grant execute on function geral_contar_admins_globais()     to authenticated;
grant execute on function geral_eh_admin_global()           to authenticated;
grant execute on function geral_eh_admin_do_modulo(text)    to authenticated;

notify pgrst, 'reload schema';
