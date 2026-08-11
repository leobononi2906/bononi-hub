-- Classificação de canal (tela do hub) + view de resumo.
-- Aplicada em 30/07/2026 no projeto vishxwdxqiygbxmtpfoy.

-- Função de classificação: atualiza o de-para E re-carimba o histórico do canal.
-- SECURITY DEFINER para conseguir dar UPDATE nas tabelas de dados sem grant amplo.
create or replace function public.umbler_classificar_canal(
  p_id_canal text,
  p_segmento text,
  p_por      text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eventos int; v_conversas int; v_mensagens int;
begin
  if p_id_canal is null or length(trim(p_id_canal)) = 0 then
    raise exception 'id_canal obrigatório';
  end if;
  if p_segmento is null or p_segmento not in
     ('atacado','varejo','assistencia','financeiro','ecommerce','pendente') then
    raise exception 'segmento inválido: %', p_segmento;
  end if;

  insert into umbler_canal_segmento (id_canal, segmento, status, classificado_por, auto_detectado)
  values (p_id_canal, p_segmento,
          case when p_segmento = 'pendente' then 'pendente' else 'classificado' end,
          p_por, false)
  on conflict (id_canal) do update
    set segmento         = excluded.segmento,
        status           = case when excluded.segmento = 'pendente' then 'pendente' else 'classificado' end,
        classificado_por = excluded.classificado_por,
        atualizado_em    = now();

  update umbler_eventos   set segmento = p_segmento where id_canal = p_id_canal;
  get diagnostics v_eventos = row_count;
  update umbler_conversas set segmento = p_segmento where id_canal = p_id_canal;
  get diagnostics v_conversas = row_count;
  update umbler_mensagens set segmento = p_segmento where id_canal = p_id_canal;
  get diagnostics v_mensagens = row_count;

  return jsonb_build_object(
    'ok', true, 'id_canal', p_id_canal, 'segmento', p_segmento,
    'eventos', v_eventos, 'conversas', v_conversas, 'mensagens', v_mensagens
  );
end;
$$;

grant execute on function public.umbler_classificar_canal(text,text,text) to authenticated;

-- View de resumo pra tela ler canal + volume numa tacada só.
create or replace view public.umbler_canais_resumo as
select
  c.id_canal, c.nome_canal, c.segmento, c.status, c.ativo,
  c.auto_detectado, c.classificado_por, c.criado_em, c.atualizado_em,
  coalesce(m.mensagens, 0) as mensagens,
  coalesce(e.eventos, 0)   as eventos,
  e.ultimo_em
from umbler_canal_segmento c
left join (select id_canal, count(*) as mensagens from umbler_mensagens group by id_canal) m
       on m.id_canal = c.id_canal
left join (select id_canal, count(*) as eventos, max(recebido_em) as ultimo_em
             from umbler_eventos group by id_canal) e
       on e.id_canal = c.id_canal;

grant select on public.umbler_canais_resumo to anon, authenticated;
