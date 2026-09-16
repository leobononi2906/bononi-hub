-- =====================================================================
-- ⚠️  SÓ PARA O BANCO DE TESTE  ⚠️
-- Libera o admin global a atribuir hierarquia A SI MESMO.
-- =====================================================================
-- ESTE ARQUIVO NÃO ESTÁ EM `migrations/` DE PROPÓSITO. Ele NÃO deve ser
-- aplicado em produção, e NÃO faz parte da migration 0003 — a migration
-- que vai para produção não tem nenhuma linha de bypass dentro dela.
--
-- POR QUE ISTO EXISTE
--   A trava "ninguém edita a própria hierarquia" é uma das boas: separa
--   quem opera de quem define poder, e é o que impede um admin de se
--   promover com o registro dizendo que foi legítimo.
--   Só que o banco de TESTE tem UM usuário. Com um usuário só, a trava
--   torna o ciclo (criar papel → atribuir → ver o espelho recalcular →
--   abrir o app) impossível de exercitar à mão no navegador.
--
-- O QUE ELE NÃO MEXE
--   Continua valendo, igual em produção: só o admin global escreve, e a
--   identidade vem do `auth.uid()` (JWT), nunca de parâmetro do front.
--   O admin de MÓDULO segue barrado. O log segue registrando tudo — e
--   agora carimba `so_teste: true` na linha, para a auto-atribuição não
--   se confundir com uma atribuição de verdade no histórico.
--
-- COMO DESFAZER (e é o que produção deve ter, sempre)
--   Re-aplicar a migration original, que restaura as duas funções:
--     npx supabase@2.117.0 db query --linked --project-ref <ref> \
--       -f supabase/migrations/0003_geral_hierarquias.sql
-- =====================================================================

-- Trava de ambiente: recusa rodar num banco com cara de produção.
-- Produção tinha ~45 usuários em 08/2026; o teste tem 1.
do $guarda$
declare v_n int;
begin
  select count(*) into v_n from auth.users;
  if v_n > 5 then
    raise exception
      'RECUSADO: este banco tem % usuarios em auth.users — tem cara de PRODUCAO. Este script e so para o banco de teste.', v_n;
  end if;
  raise notice 'banco com % usuario(s): segue como teste', v_n;
end
$guarda$;

create or replace function geral_atribuir_hierarquia(p_user uuid, p_hier bigint)
returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare v_antes jsonb; v_esp jsonb; v_propria boolean;
begin
  if not geral_eh_admin_global() then
    raise exception 'apenas o admin global pode atribuir hierarquia';
  end if;

  -- ⚠️ SÓ-TESTE: em produção esta linha é um `raise exception`.
  v_propria := (p_user = auth.uid());

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
                    jsonb_build_object('hierarquia_id', p_hier, 'espelho', v_esp,
                                       'so_teste', v_propria));

  return jsonb_build_object('ok', true, 'user_id', p_user, 'hierarquia_id', p_hier,
                            'espelho', v_esp, 'propria', v_propria);
end $fn$;

create or replace function geral_remover_hierarquia(p_user uuid)
returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare v_antes jsonb;
begin
  if not geral_eh_admin_global() then
    raise exception 'apenas o admin global pode remover hierarquia';
  end if;
  -- ⚠️ SÓ-TESTE: em produção há um `raise exception` para p_user = auth.uid().

  select to_jsonb(uh) into v_antes from geral_usuario_hierarquia uh where uh.user_id = p_user;
  delete from geral_usuario_hierarquia where user_id = p_user;
  perform geral_log('REMOVER', null, p_user, v_antes,
                    jsonb_build_object('so_teste', p_user = auth.uid()));

  return jsonb_build_object('ok', true, 'user_id', p_user, 'removida', v_antes is not null);
end $fn$;

revoke all on function geral_atribuir_hierarquia(uuid, bigint) from public, anon;
revoke all on function geral_remover_hierarquia(uuid)          from public, anon;
grant execute on function geral_atribuir_hierarquia(uuid, bigint) to authenticated;
grant execute on function geral_remover_hierarquia(uuid)          to authenticated;

notify pgrst, 'reload schema';

-- Deixa o rastro no próprio histórico do módulo, para quem abrir o log
-- depois não achar que produção se comporta assim.
insert into geral_hierarquia_log (acao, quem_email, depois)
values ('SO-TESTE', 'script',
        jsonb_build_object('o_que', 'auto-atribuicao liberada neste banco',
                           'desfazer', 'reaplicar supabase/migrations/0003_geral_hierarquias.sql'));
