-- =====================================================================
-- 0005 — Atribui as hierarquias a quem já está no grupo
-- =====================================================================
-- Este é o passo que MEXE no `user_metadata` de gente de verdade. Tudo
-- aqui foi desenhado para que ele não mude o acesso de ninguém.
--
-- A REGRA: só recebe hierarquia quem já tem EXATAMENTE aquele conjunto de
-- módulos e de admin_modulos. Combinação exata, não parecida. Quem tem um
-- módulo a mais ou a menos segue `manual` — é exceção até alguém decidir
-- que virou papel.
--
-- Por isso a atribuição é inerte: o espelho recalcula para o mesmo
-- conjunto que já estava lá.
--
-- ⚠️ A TRAVA QUE IMPORTA (§4 abaixo): depois de recalcular, o script
-- CONFERE que nenhum conjunto mudou. Se mudou, ele estoura e desfaz tudo.
-- Sem isso, "eu esperava que fosse inerte" seria fé, não prova — e um
-- erro aqui tira o acesso de gente que trabalha.
--
-- O QUE MUDA, e é só isto: quem não tinha a chave `admin_modulos` no
-- metadata passa a ter `admin_modulos: []`. Medido em 16/09/2026 num
-- ensaio com rollback: 16 pessoas, nenhuma chave sumindo, nenhum valor
-- mudando. `[]` se comporta igual a ausente em todo leitor do grupo
-- (`Array.isArray(x) && x.includes(m)` no front, `coalesce(x,'[]') @> m`
-- nas RPCs).
--
-- ADMIN GLOBAL NÃO ENTRA: `admin: true` vê tudo por definição, e a
-- hierarquia não concede admin global de propósito.
--
-- IDEMPOTENTE: rodar de novo reatribui o mesmo e recalcula o mesmo.
-- =====================================================================

do $atribui$
declare
  v_n        integer;
  v_mudaram  integer;
  r          record;
begin

  -- ---------------------------------------------------------------
  -- 1. Fotografa o estado de antes, para poder provar no fim
  -- ---------------------------------------------------------------
  create temp table _antes on commit drop as
  select id,
         (select coalesce(array_agg(m order by m), '{}') from jsonb_array_elements_text(
            coalesce(raw_user_meta_data->'modulos', '[]'::jsonb)) m) as mods,
         (select coalesce(array_agg(m order by m), '{}') from jsonb_array_elements_text(
            coalesce(raw_user_meta_data->'admin_modulos', '[]'::jsonb)) m) as adms
    from auth.users;

  -- ---------------------------------------------------------------
  -- 2. Quem casa EXATO com alguma hierarquia
  -- ---------------------------------------------------------------
  create temp table _casam on commit drop as
  with pessoa as (
    select u.id,
           (select coalesce(array_agg(m order by m), '{}') from jsonb_array_elements_text(
              coalesce(u.raw_user_meta_data->'modulos', '[]'::jsonb)) m) as mods,
           (select coalesce(array_agg(m order by m), '{}') from jsonb_array_elements_text(
              coalesce(u.raw_user_meta_data->'admin_modulos', '[]'::jsonb)) m) as adms
      from auth.users u
     -- admin global fora: ve tudo por definicao
     where not coalesce((u.raw_user_meta_data->>'admin')::boolean, false)
  ),
  hier as (
    select h.id, h.nome,
           (select coalesce(array_agg(hm.modulo order by hm.modulo), '{}') from geral_hierarquia_modulos hm
             where hm.hierarquia_id = h.id and hm.visualizar) as mods,
           (select coalesce(array_agg(hm.modulo order by hm.modulo), '{}') from geral_hierarquia_modulos hm
             where hm.hierarquia_id = h.id and hm.admin_modulo) as adms
      from geral_hierarquias h
     where not h.arquivada
  )
  select p.id as user_id, h.id as hierarquia_id, h.nome
    from pessoa p
    join hier h on p.mods = h.mods and p.adms = h.adms;

  select count(*) into v_n from _casam;
  raise notice 'casam exato: % pessoa(s)', v_n;

  -- ---------------------------------------------------------------
  -- 3. Atribui e recalcula o espelho
  -- ---------------------------------------------------------------
  insert into geral_usuario_hierarquia (user_id, hierarquia_id, atribuida_por)
  select user_id, hierarquia_id, null from _casam
  on conflict (user_id) do update
    set hierarquia_id = excluded.hierarquia_id,
        atribuida_em  = now();

  for r in select user_id, hierarquia_id, nome from _casam loop
    perform geral_recalcular_espelho(r.user_id);
    -- Rastro honesto: ninguem clicou em nada. `quem` fica nulo.
    insert into geral_hierarquia_log (quem, quem_email, acao, hierarquia_id, alvo_user, alvo_email, depois)
    values (null, 'migration 0005 (combinacao exata)', 'ATRIBUIR', r.hierarquia_id, r.user_id,
            (select email from auth.users where id = r.user_id),
            jsonb_build_object('hierarquia', r.nome, 'regra', 'modulos e admin_modulos identicos aos que a pessoa ja tinha'));
  end loop;

  -- ---------------------------------------------------------------
  -- 4. A TRAVA: provar que nenhum acesso mudou
  -- ---------------------------------------------------------------
  select count(*) into v_mudaram
    from _antes a
    join auth.users u on u.id = a.id
   where a.mods is distinct from (select coalesce(array_agg(m order by m), '{}') from jsonb_array_elements_text(
            coalesce(u.raw_user_meta_data->'modulos', '[]'::jsonb)) m)
      or a.adms is distinct from (select coalesce(array_agg(m order by m), '{}') from jsonb_array_elements_text(
            coalesce(u.raw_user_meta_data->'admin_modulos', '[]'::jsonb)) m);

  if v_mudaram > 0 then
    raise exception
      'ABORTADO: a atribuicao mudaria o acesso de % pessoa(s). Era para ser inerte. Nada foi gravado.',
      v_mudaram;
  end if;

  raise notice 'ok: % atribuidos, 0 mudancas de acesso', v_n;
end
$atribui$;

-- Conferir depois de aplicar:
--   select h.nome, count(uh.user_id)
--     from geral_hierarquias h
--     left join geral_usuario_hierarquia uh on uh.hierarquia_id = h.id
--    group by h.nome order by h.nome;
