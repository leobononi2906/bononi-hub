-- Fonte única de intake da Umbler (recebe tudo, segmenta depois)
-- Aplicada em 30/07/2026 no projeto vishxwdxqiygbxmtpfoy.

-- 1) CRU: recebe tudo, nada se perde
create table if not exists public.umbler_eventos (
  id           bigint generated always as identity primary key,
  event_id     text unique,
  tipo         text,
  id_conversa  text,
  id_contato   text,
  telefone     text,
  id_canal     text,
  nome_canal   text,
  segmento     text default 'pendente',
  payload      jsonb not null,
  recebido_em  timestamptz not null default now()
);
create index if not exists idx_umbler_eventos_conversa on public.umbler_eventos (id_conversa);
create index if not exists idx_umbler_eventos_segmento on public.umbler_eventos (segmento);
create index if not exists idx_umbler_eventos_recebido on public.umbler_eventos (recebido_em);
create index if not exists idx_umbler_eventos_canal on public.umbler_eventos (id_canal);

-- 2) De-para canal -> segmento (configurável pela tela do hub)
create table if not exists public.umbler_canal_segmento (
  id_canal         text primary key,
  nome_canal       text,
  segmento         text not null default 'pendente',
  status           text not null default 'pendente',
  ativo            boolean not null default true,
  auto_detectado   boolean not null default true,
  classificado_por text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);

-- 3) Conversas parseadas (espelha ecom_umbler_conversas + segmento)
create table if not exists public.umbler_conversas (
  id_conversa        text primary key,
  segmento           text default 'pendente',
  id_contato         text,
  telefone           text,
  nome_contato       text,
  id_canal           text,
  nome_canal         text,
  id_membro_umbler   text,
  nome_atendente     text,
  tags               text[],
  aberta             boolean,
  criada_em_umbler   timestamptz,
  ultima_mensagem_em timestamptz,
  atualizado_em      timestamptz not null default now()
);
create index if not exists idx_umbler_conversas_segmento on public.umbler_conversas (segmento);
create index if not exists idx_umbler_conversas_telefone on public.umbler_conversas (telefone);
create index if not exists idx_umbler_conversas_canal on public.umbler_conversas (id_canal);

-- 4) Mensagens parseadas (espelha ecom_umbler_mensagens + segmento)
create table if not exists public.umbler_mensagens (
  event_id         text primary key,
  id_mensagem      text,
  id_conversa      text,
  segmento         text default 'pendente',
  id_contato       text,
  telefone         text,
  nome_contato     text,
  id_canal         text,
  nome_canal       text,
  id_membro_umbler text,
  nome_atendente   text,
  direcao          text,
  tipo_mensagem    text,
  conteudo         text,
  arquivo          jsonb,
  tags             text[],
  enviado_em       timestamptz,
  recebido_em      timestamptz not null default now()
);
create index if not exists idx_umbler_mensagens_conversa on public.umbler_mensagens (id_conversa);
create index if not exists idx_umbler_mensagens_segmento on public.umbler_mensagens (segmento);
create index if not exists idx_umbler_mensagens_enviado on public.umbler_mensagens (enviado_em);
create index if not exists idx_umbler_mensagens_canal on public.umbler_mensagens (id_canal);

-- Trigger de atualizado_em no de-para
create or replace function public.umbler_touch_atualizado_em()
returns trigger language plpgsql as $$
begin
  new.atualizado_em = now();
  return new;
end;
$$;

drop trigger if exists trg_umbler_canal_touch on public.umbler_canal_segmento;
create trigger trg_umbler_canal_touch
  before update on public.umbler_canal_segmento
  for each row execute function public.umbler_touch_atualizado_em();

-- GRANTS (leitura pros apps; a função de intake grava via service_role)
grant select on public.umbler_eventos    to anon, authenticated;
grant select on public.umbler_conversas  to anon, authenticated;
grant select on public.umbler_mensagens  to anon, authenticated;
grant select on public.umbler_canal_segmento to anon, authenticated;
grant insert, update on public.umbler_canal_segmento to authenticated;
