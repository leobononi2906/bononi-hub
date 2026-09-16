-- =====================================================================
-- 0004 — Hierarquias iniciais
-- =====================================================================
-- DE ONDE ELAS SAIRAM, e por que isso importa: nenhuma foi inventada de
-- organograma. Cada uma é um agrupamento REAL do `user_metadata` das 52
-- pessoas de produção, medido em 16/09/2026 — só entraram combinações com
-- 2 ou mais pessoas. Descrever o acesso que a pessoa JÁ TEM é o que torna
-- a migração inerte: atribuir a hierarquia a quem já está no grupo não
-- muda uma linha do metadata dela.
--
-- QUEM FICOU DE FORA, e o motivo de cada um:
--
--   • Os 12 parceiros da rede autorizada. Eles não têm módulo nenhum e
--     entram no Portal do Parceiro por `prt_usuarios.user_id` →
--     `parceiro_id`, não por `modulos`. Dar a eles uma hierarquia com
--     `rede-autorizada` não mudaria nada no Portal — mas ACENDERIA o
--     cartão do app da Rede Autorizada no Hub, que é ferramenta interna.
--     Seria concessão silenciosa de privilégio, disfarçada de organização.
--
--   • Os 8 admins globais. `admin: true` vê tudo por definição, e a
--     hierarquia não concede admin global de propósito.
--
--   • Os perfis de uma pessoa só (diretoria e gerências, com 6 a 10
--     módulos cada). Uma hierarquia por pessoa não é papel, é apelido —
--     elas continuam marcadas como `manual` na tela, que é o certo: é
--     exceção até alguém decidir que virou papel.
--
--   • `expedbononi`: sem módulo e sem vínculo de parceiro. Não é papel,
--     é uma pessoa para alguém olhar.
--
-- O QUE ESTE SEED NÃO FAZ: não atribui hierarquia a ninguém. Criar é
-- inerte; ATRIBUIR é o ato que recalcula o metadata da pessoa. Isso fica
-- para o admin global, na tela do Hub, uma pessoa por vez.
--
-- SOBRE OS VERBOS (incluir/editar/excluir/aprovar/exportar): hoje NENHUM
-- app os lê — só `visualizar` e `admin_modulo` alimentam o espelho. Por
-- isso eles entram assim:
--   - módulo que a pessoa ADMINISTRA  -> todos os verbos (ela administra)
--   - módulo que ela só acessa        -> só `visualizar`, e a descrição
--     diz que falta definir
-- Inferir "pode aprovar" do metadata seria inventar autoridade: o
-- metadata não guarda verbo. Essa parte é para quem manda no processo.
--
-- IDEMPOTENTE: `on conflict (nome) do nothing`. Rodar duas vezes não
-- duplica nem sobrescreve o que alguém já editou na tela.
-- =====================================================================

do $seed$
declare
  v_id bigint;

  -- nome | descricao | modulos so-visualizar | modulos que administra
  v_papeis constant jsonb := jsonb_build_array(
    jsonb_build_object(
      'nome', 'Vendedor',
      'desc', 'Consulta as vendas por vendedor e acompanha o frete dos pedidos. '
           || 'Derivada do acesso real de 8 pessoas da equipe de vendas em 16/09/2026. '
           || 'O que pode FAZER em cada módulo ainda precisa ser definido com quem manda no processo.',
      'ver', jsonb_build_array('varejo', 'frete'),
      'adm', jsonb_build_array()),

    jsonb_build_object(
      'nome', 'Representante Stonni',
      'desc', 'Atende o cliente do atacado: catálogo, pedido e acompanhamento de frete, '
           || 'mais a consulta de vendas. Derivada do acesso real de 3 representantes em 16/09/2026. '
           || 'O que pode FAZER em cada módulo ainda precisa ser definido com quem manda no processo.',
      'ver', jsonb_build_array('atacado', 'stonni', 'varejo', 'frete'),
      'adm', jsonb_build_array()),

    jsonb_build_object(
      'nome', 'Comprador',
      'desc', 'Cuida de estoque, reposição e pedido de compra, e acompanha o frete do que vem chegando. '
           || 'Derivada do acesso real de 3 pessoas de compras em 16/09/2026. '
           || 'O que pode FAZER em cada módulo — em especial aprovar pedido, e até que valor — '
           || 'ainda precisa ser definido com quem manda no processo.',
      'ver', jsonb_build_array('compras', 'frete'),
      'adm', jsonb_build_array()),

    jsonb_build_object(
      'nome', 'Expedição — administrador',
      'desc', 'Opera a expedição e a administra: configura a operação, libera NF presa em picking '
           || 'e gerencia quem entra. Derivada do acesso real de 2 pessoas em 16/09/2026, que já '
           || 'constavam como admin do módulo.',
      'ver', jsonb_build_array(),
      'adm', jsonb_build_array('expedicao')),

    jsonb_build_object(
      'nome', 'Comercial Stonni — consulta',
      'desc', 'Acessa o portal comercial da Stonni, sem o atacado nem a consulta de vendas. '
           || 'Derivada do acesso real de 2 pessoas em 16/09/2026. '
           || 'O que pode FAZER ainda precisa ser definido com quem manda no processo.',
      'ver', jsonb_build_array('stonni'),
      'adm', jsonb_build_array())
  );

  r jsonb;
  m text;
begin
  for r in select * from jsonb_array_elements(v_papeis) loop
    insert into geral_hierarquias (nome, descricao, empresas, criada_por)
    values (r ->> 'nome', r ->> 'desc', '{}', null)
    on conflict (nome) do nothing
    returning id into v_id;

    -- Já existia: não sobrescreve o que alguém editou na tela.
    if v_id is null then
      raise notice 'hierarquia % ja existe, pulando', r ->> 'nome';
      continue;
    end if;

    -- Módulo que ela só acessa: `visualizar`, e nada mais. Os outros
    -- verbos ficam falsos porque o metadata não guarda verbo — inferir
    -- seria inventar autoridade.
    for m in select * from jsonb_array_elements_text(r -> 'ver') loop
      insert into geral_hierarquia_modulos (hierarquia_id, modulo, visualizar)
      values (v_id, m, true);
    end loop;

    -- Módulo que ela ADMINISTRA: aí os verbos são defensáveis, porque
    -- administrar o módulo é poder fazer o que ele faz.
    for m in select * from jsonb_array_elements_text(r -> 'adm') loop
      insert into geral_hierarquia_modulos
        (hierarquia_id, modulo, visualizar, incluir, editar, excluir, aprovar, exportar, admin_modulo)
      values (v_id, m, true, true, true, true, true, true, true);
    end loop;

    -- Rastro honesto: ninguém clicou em nada. `quem` fica nulo porque
    -- não houve pessoa, e o e-mail diz o que foi.
    insert into geral_hierarquia_log (quem, quem_email, acao, hierarquia_id, depois)
    values (null, 'seed 0004 (derivado do metadata de producao)', 'CRIAR', v_id,
            jsonb_build_object('nome', r ->> 'nome', 'origem', 'agrupamento real de 16/09/2026'));
  end loop;
end
$seed$;

-- Conferir depois de aplicar:
--   select nome, descricao, pessoas from jsonb_to_recordset(geral_listar_hierarquias(true))
--     as x(nome text, descricao text, pessoas int);
-- `pessoas` tem de vir 0 em todas: este seed cria, não atribui.
