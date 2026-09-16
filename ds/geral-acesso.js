/* ============================================================
   geral-acesso.js — "Quem tem acesso aqui"  |  v2 — 16/09/2026
   ============================================================
   O módulo LEITOR das hierarquias, para colar em qualquer app do grupo.

   POR QUE ELE É SÓ LEITURA, e isso não é preguiça: o CRUD de permissão
   mora num lugar só (o Hub). Duplicá-lo em 17 apps seriam 17 telas para
   auditar e 17 lugares para introduzir furo — e o que se perde numa tela
   gêmea aqui não é um `finally`, é uma trava. O que cada app ganha é
   responder "quem liberou isso pro fulano?" sem dar a ninguém o poder de
   mudar.

   QUEM ENXERGA: o admin global e o admin DAQUELE módulo. Mais ninguém —
   e é a própria RPC que decide, pelo JWT, não este arquivo.

   COMO USAR (2 linhas no app):

     <script src="ds/geral-acesso.js?v=2"></script>
     GeralAcesso.montar({ alvo:'quem-tem-acesso', modulo:'compras',
                          url:SUPA_URL, key:SUPA_KEY, sb });

   Se o container não existir, se a pessoa não puder ver, ou se a migration
   0003 ainda não tiver sido aplicada neste banco, ele não desenha nada e
   não quebra o app. Silêncio é o comportamento certo aqui: um painel de
   permissão meio carregado é pior que painel nenhum.

   PORTABILIDADE DE COR — por que todo token aqui tem fallback:
   este módulo roda em app Bononi E em app Stonni, e os dois DS não têm os
   mesmos nomes. Medido em 16/09/2026: `--status-ok-bg`, `--status-info-bg`,
   `--text-accent` e `--fs-11/12/13` **não existem** no `stonni-ds.css`; e
   `--border`, `--surface` e `--muted` não existem em DS nenhum — vêm da
   ponte de variáveis que Hub e Compras têm no `:root`.
   Token inexistente **não dá erro**: a declaração fica inválida e a cor cai
   no valor inicial, que para `background` é transparente. O painel sumiria
   sem nada no console. Por isso cada cor é `var(--token-do-app, fallback)`,
   resolvida uma vez em `--ga-*` no elemento raiz do painel: onde o app tem
   o token, ele manda; onde não tem, o fallback segura.

   ESTE ARQUIVO É CÓPIA VERBATIM. A original vive em bononi-hub/ds/.
   Mudou aqui? Mude lá e recopie para todos — como já se faz com o
   bononi-ds.css. Confira com:  cmp ds/geral-acesso.js <hub>/ds/geral-acesso.js
   ============================================================ */
(function () {
  'use strict';

  var VERSAO = '2';

  // Ponte de tokens: o app manda quando tem o token; o fallback segura
  // quando não tem. Ver "PORTABILIDADE DE COR" no cabeçalho.
  var TOKENS = [
    '--ga-border:var(--border,var(--border-subtle,#e2e5ea))',
    '--ga-surface:var(--surface,var(--surface-card,#fff))',
    '--ga-sunken:var(--surface-sunken,var(--bg2,#f5f6f8))',
    '--ga-text:var(--text,var(--text-body,#14161a))',
    '--ga-muted:var(--muted,var(--text-muted,#6b7382))',
    '--ga-ok-bg:var(--status-ok-bg,#e6f4ea)',
    '--ga-ok-fg:var(--status-ok-text,#1a7f37)',
    '--ga-info-bg:var(--status-info-bg,#e7f0fb)',
    '--ga-info-fg:var(--status-info-text,#1f5fa8)',
    '--ga-accent:var(--text-accent,var(--action-primary,#c11f25))',
    '--ga-r-sm:var(--radius-sm,6px)',
    '--ga-r-lg:var(--radius-lg,12px)',
    '--ga-f11:var(--fs-11,11px)',
    '--ga-f12:var(--fs-12,12px)',
    '--ga-f13:var(--fs-13,13px)'
  ].join(';');

  var ACOES = ['incluir', 'editar', 'excluir', 'aprovar', 'exportar'];

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function chip(txt, tipo) {
    var css = tipo === 'ok'
      ? 'background:var(--ga-ok-bg);color:var(--ga-ok-fg);border:1px solid var(--ga-ok-bg);font-weight:700'
      : tipo === 'info'
        ? 'background:var(--ga-info-bg);color:var(--ga-info-fg);border:1px solid var(--ga-info-bg);font-weight:700'
        : 'background:var(--ga-sunken);color:var(--ga-muted);border:1px dashed var(--ga-border)';
    return '<span style="' + css + ';font-size:var(--ga-f11);padding:3px 9px;border-radius:var(--ga-r-sm);white-space:nowrap">' + txt + '</span>';
  }

  function linha(p) {
    var nome = esc(p.nome || p.email || '—');
    var papel = p.hierarquia
      ? '<span title="' + esc(p.hierarquia_descricao || '') + '">' + chip(esc(p.hierarquia), 'neutro') + '</span>'
      : chip('manual', 'neutro');

    // O que a hierarquia permite AQUI. Sem hierarquia não há o que dizer —
    // e dizer "tudo" seria mentira, porque o metadata não guarda verbo.
    var perm = p.permissoes || null;
    var podem = perm ? ACOES.filter(function (a) { return perm[a]; }) : [];
    var acoes = !p.hierarquia
      ? '<span style="color:var(--ga-muted);font-size:var(--ga-f11)">não registrado em papel nenhum</span>'
      : podem.length
        ? podem.map(function (a) { return chip(a, 'neutro'); }).join(' ')
        : '<span style="color:var(--ga-muted);font-size:var(--ga-f11)">só visualizar</span>';

    var selo = p.admin_global ? chip('ADMIN GLOBAL', 'info')
             : p.admin_modulo ? chip('admin daqui', 'ok') : '';

    var ultimo = p.ultimo_acesso
      ? new Date(p.ultimo_acesso).toLocaleDateString('pt-BR')
      : 'Nunca';

    return '<tr style="border-top:1px solid var(--ga-border)">' +
      '<td style="padding:9px 12px"><div style="font-weight:600;font-size:var(--ga-f13)">' + nome + '</div>' +
        '<div style="font-size:var(--ga-f11);color:var(--ga-muted)">' + esc(p.email || '') + '</div></td>' +
      '<td style="padding:9px 12px">' + papel + ' ' + selo + '</td>' +
      '<td style="padding:9px 12px;line-height:2">' + acoes + '</td>' +
      '<td style="padding:9px 12px;font-size:var(--ga-f11);color:var(--ga-muted);white-space:nowrap">' + ultimo + '</td>' +
      '</tr>';
  }

  function desenhar(el, dados, modulo) {
    var pessoas = (dados && dados.pessoas) || [];
    var semPapel = pessoas.filter(function (p) { return !p.hierarquia && !p.admin_global; }).length;

    el.innerHTML =
      '<div style="' + TOKENS + ';border:1px solid var(--ga-border);border-radius:var(--ga-r-lg);background:var(--ga-surface);color:var(--ga-text);overflow:hidden">' +
        '<div style="display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;padding:13px 16px;border-bottom:1px solid var(--ga-border)">' +
          '<div>' +
            '<div style="font-size:var(--ga-f13);font-weight:700">Quem tem acesso aqui</div>' +
            '<div style="font-size:var(--ga-f11);color:var(--ga-muted);margin-top:2px">' +
              pessoas.length + (pessoas.length === 1 ? ' pessoa' : ' pessoas') +
              (semPapel ? ' — ' + semPapel + ' sem hierarquia (acesso marcado à mão)' : '') +
            '</div>' +
          '</div>' +
          '<a href="https://bononi-hub.vercel.app/" target="_blank" rel="noopener"' +
            ' style="font-size:var(--ga-f12);color:var(--ga-accent);text-decoration:none;font-weight:600">' +
            'Mudar acesso no Hub →</a>' +
        '</div>' +
        (pessoas.length
          ? '<div style="overflow-x:auto"><table style="width:100%;border-collapse:collapse;font-size:var(--ga-f12)">' +
              '<thead><tr style="background:var(--ga-sunken);text-align:left">' +
                '<th style="padding:8px 12px;font-weight:700">Pessoa</th>' +
                '<th style="padding:8px 12px;font-weight:700">Hierarquia</th>' +
                '<th style="padding:8px 12px;font-weight:700">Pode, aqui</th>' +
                '<th style="padding:8px 12px;font-weight:700">Último acesso</th>' +
              '</tr></thead><tbody>' + pessoas.map(linha).join('') + '</tbody></table></div>'
          : '<div style="padding:24px;text-align:center;color:var(--ga-muted);font-size:var(--ga-f13)">Ninguém além dos administradores globais.</div>') +
        '<p style="margin:0;padding:10px 16px;border-top:1px solid var(--ga-border);background:var(--ga-sunken);font-size:var(--ga-f11);color:var(--ga-muted);line-height:1.5">' +
          'Isto é o que a hierarquia <b>autoriza</b> em ' + esc(modulo) + '. Enquanto o app não bater no banco com o token do ' +
          'usuário, é o que a pessoa <b>vê</b> — não o que a API impede.' +
        '</p>' +
      '</div>';
  }

  var GeralAcesso = {
    versao: VERSAO,

    /**
     * @param {object}  o
     * @param {string|Element} o.alvo   container (id ou elemento)
     * @param {string}  o.modulo        chave de acesso do app ('compras', 'financeiro'…)
     * @param {string}  o.url           SUPA_URL
     * @param {string}  o.key           SUPA_KEY (anon)
     * @param {object=} o.sb            client supabase-js (para pegar a sessão)
     * @param {function=} o.token       alternativa ao `sb`: devolve o access_token
     */
    montar: async function (o) {
      var el = typeof o.alvo === 'string' ? document.getElementById(o.alvo) : o.alvo;
      if (!el) return false;
      el.innerHTML = '';

      var tk = null;
      try {
        if (o.token) tk = await o.token();
        else if (o.sb) tk = (await o.sb.auth.getSession()).data.session?.access_token;
      } catch (e) { /* sem sessão: cai no return abaixo */ }
      // Sem token não há identidade, e a RPC se recusa — nem vale a ida.
      if (!tk) return false;

      try {
        var resp = await fetch(o.url + '/rest/v1/rpc/geral_quem_tem_acesso', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'apikey': o.key,
            'Authorization': 'Bearer ' + tk,
          },
          body: JSON.stringify({ p_modulo: o.modulo }),
        });
        if (!resp.ok) {
          // 404 = migration 0003 ainda não aplicada neste banco. Não é erro
          // do app: fica quieto em vez de mostrar caixa quebrada.
          console.warn('[geral-acesso] RPC indisponível (HTTP ' + resp.status + ')');
          return false;
        }
        var dados = await resp.json();
        // A RPC devolve {erro:'sem permissao'} para quem não pode ver.
        // Quem não pode ver não vê nem a moldura.
        if (!dados || dados.erro) return false;

        desenhar(el, dados, o.modulo);
        if (typeof window.hydrateIcons === 'function') window.hydrateIcons(el);
        return true;
      } catch (e) {
        console.warn('[geral-acesso]', e && e.message);
        return false;
      }
    },
  };

  window.GeralAcesso = GeralAcesso;
})();
