-- =====================================================================
-- TESTE DE GRANT — o que o papel `authenticated` consegue de verdade
-- =====================================================================
-- POR QUE ESTE ARQUIVO EXISTE, separado do teste do ciclo:
--   o `0003_hierarquias_ciclo.sql` roda como o papel do CLI (superusuario)
--   e so troca o `request.jwt.claims`. Isso prova a LOGICA das funcoes —
--   quem e admin, quais travas disparam — mas NAO prova o `grant`, porque
--   superusuario passa por cima de grant.
--
--   O buraco que isso deixaria: `revoke all ... from public, anon` sem o
--   `grant execute ... to authenticated` correspondente daria 19/19 no
--   ciclo e uma tela MORTA para o admin de verdade, com 401 em tudo.
--
--   Aqui tem `set local role authenticated`, que e o que o PostgREST faz
--   com o token de quem esta logado. Ai o grant conta.
--
-- O QUE TEM DE DAR:
--   as 5 funcoes -> ok
--   SELECT direto na tabela -> BARRADO (RLS ligada + revoke; o unico
--   caminho e pelas funcoes `security definer`)
--
-- Tudo em BEGIN/ROLLBACK. Rodado em 16/09/2026 em producao
-- (vishxwdxqiygbxmtpfoy): 6/6, e o banco voltou limpo.
--
--   npx supabase@2.117.0 db query --linked --project-ref <ref> \
--     -f supabase/testes/0003_grants_authenticated.sql
--
-- OBS: os inserts no `_r` ficam DEPOIS do `reset role` de proposito —
-- `authenticated` nao escreve nem em temp table, e o teste morreria ali.
-- =====================================================================
begin;
create temp table _r (n int generated always as identity, teste text, resultado text);

do $x$
declare
  v_admin uuid;
  r1 text; r2 text; r3 text; r4 text; r5 text; r6 text;
begin
  select id into v_admin from auth.users
   where coalesce((raw_user_meta_data->>'admin')::boolean,false) order by created_at limit 1;
  perform set_config('request.jwt.claims',
           json_build_object('sub', v_admin, 'role','authenticated')::text, true);

  -- Troca o ROLE de verdade, como o PostgREST faz. So assim o grant e testado.
  set local role authenticated;

  begin r1 := 'ok -> '||left(geral_listar_hierarquias(true)::text,45);
  exception when others then r1 := 'FALHOU -> '||sqlerrm; end;

  begin r2 := 'ok -> '||left(geral_listar_atribuicoes()::text,45);
  exception when others then r2 := 'FALHOU -> '||sqlerrm; end;

  begin r3 := 'ok -> '||left(geral_quem_tem_acesso('compras')::text,45);
  exception when others then r3 := 'FALHOU -> '||sqlerrm; end;

  begin r4 := 'ok -> '||left(geral_salvar_hierarquia(null,'ZZ grant','teste de grant','{}'::int[],null,'[]'::jsonb)::text,45);
  exception when others then r4 := 'FALHOU -> '||sqlerrm; end;

  begin r5 := 'ok -> '||left(geral_log_recente(5)::text,45);
  exception when others then r5 := 'FALHOU -> '||sqlerrm; end;

  -- A tabela direto tem de continuar barrada, mesmo para authenticated.
  begin
    perform 1 from geral_hierarquias limit 1;
    r6 := 'FALHOU: leu a tabela direto';
  exception when others then r6 := 'barrado (correto) -> '||left(sqlerrm,40); end;

  reset role;

  insert into _r (teste, resultado) values
    ('listar_hierarquias   como authenticated', r1),
    ('listar_atribuicoes   como authenticated', r2),
    ('quem_tem_acesso      como authenticated', r3),
    ('salvar_hierarquia    como authenticated', r4),
    ('log_recente          como authenticated', r5),
    ('SELECT direto na tabela (tem de barrar)', r6);
end
$x$;

select n, teste, resultado from _r order by n;
rollback;
