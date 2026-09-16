-- =====================================================================
-- 0006 — Verbos das hierarquias, e correção de dois nomes
-- =====================================================================
-- Os verbos (incluir/editar/excluir/aprovar/exportar) não estavam
-- preenchidos porque o `user_metadata` não guarda verbo — inferir dele
-- seria inventar autoridade. Então foram buscados onde eles existem de
-- verdade: nas trilhas de auditoria dos apps e nas tabelas de permissão
-- que cada app já tem. Cada célula abaixo tem uma razão escrita.
--
-- ⚠️ ISTO NÃO MUDA O ACESSO DE NINGUÉM. Só `visualizar` e `admin_modulo`
-- alimentam o espelho, e nenhum dos dois é tocado aqui. A trava no fim
-- prova isso e desfaz tudo se algum metadata mudar.
--
-- E nenhum app LÊ esses verbos hoje — são documentação. Mas documentação
-- errada engana pior que documentação ausente, e por isso eles vieram de
-- evidência, não de suposição.
--
-- ---------------------------------------------------------------------
-- OS DOIS NOMES ESTAVAM TROCADOS, e a evidência é dura:
--
--   `ped_representantes` (ativos) = alexandreriellaoficial, eusoupamellasantos
--      -> são esses os REPRESENTANTES, e eles têm só a chave `stonni`.
--         Estavam chamados de "Comercial Stonni — consulta".
--
--   comercial.stonni02, comercial2stonni, comercialstonni.ana
--      -> não estão em `ped_representantes` NEM em `ped_gestores`, mas
--         têm a chave `atacado`, que é a que abre o CRM interno
--         (`ehInterno()` no com_stonni). São o time comercial de dentro.
--         Estavam chamados de "Representante Stonni".
--
-- Renomear é seguro: o espelho não depende do nome, e as atribuições
-- apontam por id.
-- ---------------------------------------------------------------------

do $verbos$
declare
  v_mudaram int;
  v_id      bigint;
begin

  create temp table _antes on commit drop as
  select id,
         (select coalesce(array_agg(m order by m), '{}') from jsonb_array_elements_text(
            coalesce(raw_user_meta_data->'modulos', '[]'::jsonb)) m) as mods,
         (select coalesce(array_agg(m order by m), '{}') from jsonb_array_elements_text(
            coalesce(raw_user_meta_data->'admin_modulos', '[]'::jsonb)) m) as adms
    from auth.users;

  -- =================================================================
  -- 1. Corrige os dois nomes trocados
  -- =================================================================
  update geral_hierarquias
     set nome = 'Comercial Stonni — interno',
         descricao = 'Time comercial de dentro da casa: atende o cliente do atacado e enxerga o CRM '
                  || '(a chave `atacado` é a que abre o CRM no Comercial Stonni). Também acompanha frete '
                  || 'e consulta vendas. Derivada do acesso real de 3 pessoas em 16/09/2026 — que não '
                  || 'estão em `ped_representantes` nem em `ped_gestores`, e por isso NÃO aprovam pedido.',
         alterada_em = now()
   where nome = 'Representante Stonni';

  update geral_hierarquias
     set nome = 'Representante Stonni',
         descricao = 'Representante externo: acessa o portal do Comercial Stonni para catálogo e pedido, '
                  || 'sem o CRM interno. Derivada do acesso real de 2 pessoas em 16/09/2026, ambas '
                  || 'cadastradas e ativas em `ped_representantes`. Não aprovam pedido — `pode_aprovar` '
                  || 'mora em `ped_gestores`, onde elas não estão.',
         alterada_em = now()
   where nome = 'Comercial Stonni — consulta';

  -- =================================================================
  -- 2. Verbos, com a razão de cada um
  -- =================================================================

  -- ---- Vendedor ----------------------------------------------------
  -- `varejo`: 74 eventos em varejo_logs. MIDIA_UP = incluir mídia;
  --           ENVIO_COMPARTILHAR/COPIAR/WA_DIRETO = exportar.
  --           Nada de editar/excluir/aprovar no rastro, e a aba Config
  --           do app é só de admin.
  select id into v_id from geral_hierarquias where nome = 'Vendedor';
  update geral_hierarquia_modulos
     set incluir = true, exportar = true
   where hierarquia_id = v_id and modulo = 'varejo';
  -- `frete`: o app NÃO TEM LOGIN ("sem login — acesso direto", no próprio
  --          código). A chave só acende o cartão no Hub, então visualizar
  --          é tudo o que ela significa de verdade.

  -- ---- Comercial Stonni — interno ---------------------------------
  select id into v_id from geral_hierarquias where nome = 'Comercial Stonni — interno';
  -- `atacado` abre o CRM: cadastrar e manter cliente, e tirar PDF.
  update geral_hierarquia_modulos
     set incluir = true, editar = true, exportar = true
   where hierarquia_id = v_id and modulo = 'atacado';
  -- `stonni` é o portal: lançar pedido e gerar o PDF do pedido/orçamento.
  update geral_hierarquia_modulos
     set incluir = true, exportar = true
   where hierarquia_id = v_id and modulo = 'stonni';
  -- `varejo`: 11 eventos, só ENVIO_* -> exportar. Sem incluir.
  update geral_hierarquia_modulos
     set exportar = true
   where hierarquia_id = v_id and modulo = 'varejo';
  -- `frete`: idem Vendedor — só visualizar.
  -- `aprovar` fica FALSO nos quatro: nenhuma das 3 está em ped_gestores,
  -- que é a tabela onde `pode_aprovar` existe de fato.

  -- ---- Representante Stonni ---------------------------------------
  select id into v_id from geral_hierarquias where nome = 'Representante Stonni';
  -- `stonni`: são representantes ativos — lançam pedido e tiram PDF.
  --           Não editam catálogo (`pode_catalogo` é de gestor) e não
  --           aprovam (`pode_aprovar` idem).
  update geral_hierarquia_modulos
     set incluir = true, exportar = true
   where hierarquia_id = v_id and modulo = 'stonni';

  -- ---- Comprador ---------------------------------------------------
  select id into v_id from geral_hierarquias where nome = 'Comprador';
  -- `compras`: no comp_audit_log, Eder e Elivelton registram
  --            `pedido_salvo` (incluir) e `importacao/import_processo(s)`
  --            (incluir + editar). Exportar é o pedido em CSV/PDF.
  --            APROVAR FICA FALSO, e a razão é medida: TODO pedido de
  --            compra em produção está em `status = 'rascunho'`. Nenhum
  --            foi aprovado — aprovação não é conceito vivo neste app
  --            hoje. Marcar `aprovar` aqui documentaria uma etapa que
  --            não existe.
  update geral_hierarquia_modulos
     set incluir = true, editar = true, exportar = true
   where hierarquia_id = v_id and modulo = 'compras';
  -- `frete`: só visualizar, mesmo motivo.

  -- ---- Expedição — administrador ----------------------------------
  -- Já veio com todos os verbos no seed 0004, porque administra o módulo.
  -- Confirmado pelo rastro: 110 eventos em exp_logs —
  -- DANFE_PDF_IMPORTADA, REGISTRAR_COLETA, CONFERENCIA_PAUSADA. Mantido.

  -- =================================================================
  -- 3. Log
  -- =================================================================
  insert into geral_hierarquia_log (quem, quem_email, acao, hierarquia_id, depois)
  select null, 'migration 0006 (verbos por evidencia)', 'EDITAR', h.id,
         jsonb_build_object(
           'o_que', 'verbos preenchidos a partir das trilhas de auditoria e das tabelas de permissao dos apps',
           'modulos', (select jsonb_agg(to_jsonb(hm) - 'hierarquia_id' order by hm.modulo)
                         from geral_hierarquia_modulos hm where hm.hierarquia_id = h.id))
    from geral_hierarquias h
   where not h.arquivada;

  -- =================================================================
  -- 4. A TRAVA: verbo não pode mexer no espelho
  -- =================================================================
  -- Só `visualizar` e `admin_modulo` alimentam o metadata, e nenhum dos
  -- dois foi tocado. Se mesmo assim algo mudou, é bug — desfaz tudo.
  select count(*) into v_mudaram
    from _antes a
    join auth.users u on u.id = a.id
   where a.mods is distinct from (select coalesce(array_agg(m order by m), '{}') from jsonb_array_elements_text(
            coalesce(u.raw_user_meta_data->'modulos', '[]'::jsonb)) m)
      or a.adms is distinct from (select coalesce(array_agg(m order by m), '{}') from jsonb_array_elements_text(
            coalesce(u.raw_user_meta_data->'admin_modulos', '[]'::jsonb)) m);

  if v_mudaram > 0 then
    raise exception 'ABORTADO: preencher verbo mudou o acesso de % pessoa(s). Nada foi gravado.', v_mudaram;
  end if;

  raise notice 'ok: verbos preenchidos, 0 mudancas de acesso';
end
$verbos$;
