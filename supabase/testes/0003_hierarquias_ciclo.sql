-- =====================================================================
-- TESTE DO CICLO — hierarquias de acesso (migration 0003)
-- =====================================================================
-- Roda as 19 checagens do modulo contra um banco de verdade, com a
-- identidade vindo do JWT simulado (set_config request.jwt.claims), que e
-- como o PostgREST faz. Cobre: admin global x admin de modulo x nao-admin,
-- as travas, o espelho e o log.
--
-- TUDO DENTRO DE BEGIN/ROLLBACK. Nada persiste, nem o usuario sintetico
-- que ele cria para receber a hierarquia (ninguem edita a propria, entao o
-- teste precisa de duas pessoas).
--
-- Como rodar:
--   npx supabase@2.117.0 db query --linked --project-ref <ref> --     -f supabase/testes/0003_hierarquias_ciclo.sql
--
-- Rodado em 16/09/2026 no banco de teste (gxzhuewczlixksqrmjuk): 19/19.
-- Vale rodar de novo antes de aplicar em producao — e depois, para provar
-- que a producao se comporta igual.
--
-- OBS: o `bigserial` NAO volta no rollback; os ids das hierarquias de teste
-- ficam consumidos. E inofensivo.
-- =====================================================================

-- Ciclo completo do modulo de hierarquias, no banco de TESTE.
-- Tudo dentro de BEGIN/ROLLBACK: nada persiste, nem o usuario sintetico.
begin;

create temp table _r (n int generated always as identity, teste text, esperado text, resultado text);
create temp table _ctx as
select id as admin_id,
       '11111111-2222-3333-4444-555555555555'::uuid as alvo_id
  from auth.users
 where coalesce((raw_user_meta_data->>'admin')::boolean, false)
 limit 1;

-- Usuario sintetico para receber a hierarquia (ninguem edita a propria).
insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                        created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
select '00000000-0000-0000-0000-000000000000', alvo_id, 'authenticated', 'authenticated',
       'alvo-teste@local', 'x', now(), now(), '{}'::jsonb,
       -- Comeca com acesso LEGADO, incluindo varejo_admin: e a chave que
       -- sumiria em silencio se a matriz nao a conhecesse.
       '{"nome":"Alvo de Teste","modulos":["compras","varejo_admin"],"admin_modulos":[]}'::jsonb
  from _ctx;

do $roteiro$
declare
  v_admin uuid; v_alvo uuid; v_hier bigint; v_tmp text;
  procedure_dummy int;
begin
  select admin_id, alvo_id into v_admin, v_alvo from _ctx;

  -- ============ como ADMIN GLOBAL ============
  perform set_config('request.jwt.claims',
           json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

  insert into _r (teste, esperado, resultado) values
    ('1. eh_admin_global', 'true', geral_eh_admin_global()::text);

  -- 2. criar hierarquia
  v_tmp := geral_salvar_hierarquia(null, 'Comprador de teste',
             'Lanca pedido de compra. Nao aprova.',
             array[1]::int[], null,
             '[{"modulo":"compras","visualizar":true,"incluir":true,"editar":true,"exportar":true},
               {"modulo":"expedicao","visualizar":true,"admin_modulo":true}]'::jsonb)::text;
  insert into _r (teste, esperado, resultado) values ('2. salvar_hierarquia', 'ok=true, afetados=0', v_tmp);
  select id into v_hier from geral_hierarquias where nome = 'Comprador de teste';

  -- 3. sem descricao tem de FALHAR
  begin
    perform geral_salvar_hierarquia(null, 'Sem descricao', '   ', '{}'::int[], null, '[]'::jsonb);
    insert into _r (teste, esperado, resultado) values ('3. salvar sem descricao', 'RECUSA', 'FALHOU: aceitou');
  exception when others then
    insert into _r (teste, esperado, resultado) values ('3. salvar sem descricao', 'RECUSA', 'recusou: ' || sqlerrm);
  end;

  -- 4. atribuir + espelho
  v_tmp := geral_atribuir_hierarquia(v_alvo, v_hier)::text;
  insert into _r (teste, esperado, resultado) values ('4. atribuir', 'ok=true', v_tmp);

  select raw_user_meta_data::text into v_tmp from auth.users where id = v_alvo;
  insert into _r (teste, esperado, resultado) values
    ('5. espelho do alvo', 'modulos=[compras,expedicao], admin_modulos=[expedicao], varejo_admin SAIU', v_tmp);

  -- 6. propria hierarquia tem de FALHAR
  begin
    perform geral_atribuir_hierarquia(v_admin, v_hier);
    insert into _r (teste, esperado, resultado) values ('6. atribuir a si mesmo', 'RECUSA', 'FALHOU: deixou');
  exception when others then
    insert into _r (teste, esperado, resultado) values ('6. atribuir a si mesmo', 'RECUSA', 'recusou: ' || sqlerrm);
  end;

  -- ============ como NAO-ADMIN (o alvo, que virou admin do modulo expedicao) ============
  perform set_config('request.jwt.claims',
           json_build_object('sub', v_alvo, 'role', 'authenticated')::text, true);

  insert into _r (teste, esperado, resultado) values
    ('7. eh_admin_global como nao-admin', 'false', geral_eh_admin_global()::text);
  insert into _r (teste, esperado, resultado) values
    ('7b. eh_admin_do_modulo(expedicao)', 'true', geral_eh_admin_do_modulo('expedicao')::text);

  begin
    perform geral_salvar_hierarquia(null, 'invasor', 'x', '{}'::int[], null, '[]'::jsonb);
    insert into _r (teste, esperado, resultado) values ('8. nao-admin cria hierarquia', 'RECUSA', 'FALHOU: criou');
  exception when others then
    insert into _r (teste, esperado, resultado) values ('8. nao-admin cria hierarquia', 'RECUSA', 'recusou: ' || sqlerrm);
  end;

  begin
    perform geral_atribuir_hierarquia(v_admin, v_hier);
    insert into _r (teste, esperado, resultado) values ('9. admin de MODULO atribui', 'RECUSA', 'FALHOU: atribuiu');
  exception when others then
    insert into _r (teste, esperado, resultado) values ('9. admin de MODULO atribui', 'RECUSA', 'recusou: ' || sqlerrm);
  end;

  -- 10/11. o leitor
  insert into _r (teste, esperado, resultado) values
    ('10. quem_tem_acesso(expedicao) sendo admin dele', 'lista as pessoas',
     left((geral_quem_tem_acesso('expedicao')->'pessoas')::text, 400));
  insert into _r (teste, esperado, resultado) values
    ('11. quem_tem_acesso(financeiro) NAO sendo admin dele', 'erro=sem permissao',
     geral_quem_tem_acesso('financeiro')::text);
  insert into _r (teste, esperado, resultado) values
    ('12. efetivo_usuario como nao-admin', 'erro=sem permissao',
     geral_efetivo_usuario(v_alvo)::text);

  -- ============ de volta como ADMIN GLOBAL ============
  perform set_config('request.jwt.claims',
           json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

  insert into _r (teste, esperado, resultado) values
    ('13. efetivo_usuario como admin', 'excecoes marca o legado',
     left(geral_efetivo_usuario(v_alvo)::text, 500));

  -- 14/15. arquivar zera o espelho de quem a tem
  v_tmp := geral_arquivar_hierarquia(v_hier, true)::text;
  insert into _r (teste, esperado, resultado) values ('14. arquivar', 'ok=true, afetados=1', v_tmp);
  select raw_user_meta_data::text into v_tmp from auth.users where id = v_alvo;
  insert into _r (teste, esperado, resultado) values
    ('15. espelho depois de arquivar', 'modulos=[] (intencional)', v_tmp);

  -- 16/17. quem NAO tem hierarquia nao pode ser tocado
  insert into _r (teste, esperado, resultado) values
    ('16. recalcular quem nao tem hierarquia', 'ok=false, metadata preservado',
     geral_recalcular_espelho(v_admin)::text);
  select raw_user_meta_data::text into v_tmp from auth.users where id = v_admin;
  insert into _r (teste, esperado, resultado) values
    ('17. metadata do admin intacto', 'admin=true e modulos originais', left(v_tmp, 300));

  -- 18. log
  select string_agg(acao || ' por ' || coalesce(quem_email,'?') ||
                    coalesce(' -> ' || alvo_email, ''), ' | ' order by id)
    into v_tmp from geral_hierarquia_log;
  insert into _r (teste, esperado, resultado) values ('18. log', 'CRIAR, ATRIBUIR, ARQUIVAR', v_tmp);
end
$roteiro$;

select n, teste, esperado, resultado from _r order by n;

rollback;
