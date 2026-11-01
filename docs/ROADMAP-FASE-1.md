# Fase 1 — MVP do piloto: roteiro por etapas

Objetivo (guia, seção 15): um leilão real com 3 a 5 lotes e 20 a 30 compradores convidados.

| # | Etapa | Status |
|---|---|---|
| 1 | **Fundação**: projeto Next.js (PWA), banco multi-tenant com RLS, motor de lances (seção 7) com os 12 testes obrigatórios, página inicial | ✅ feito |
| 2 | Login por celular (OTP), cadastro, envio de documentos, consentimentos e opt-in de WhatsApp | ✅ feito |
| 3 | Página do lote: vídeo, fotos, laudo, ficha, cronômetro, lance rápido com confirmação, lance automático, histórico | próxima |
| 4 | Painel admin: fila de cadastros, cadastro de lotes (mídias), leilões e agendamento, ao vivo, pós-venda com "Marcar como pago" | |
| 5 | Notificações: despachante de push + WhatsApp Cloud API (coberto, dou-lhe 3, arremate, cadastro aprovado) | |
| 6 | Meus lances, Minhas compras (simples), Perfil, Preferências de aviso; service worker | |
| 7 | Ensaio geral com leilão de teste, ajustes e publicação | |

## O que a etapa 1 entregou

**Banco (`supabase/migrations`)**
- Todas as tabelas da seção 13, com `tenant_id`, `criado_em`, `atualizado_em`, mais: `super_admins`,
  `configuracoes_padrao`, `consentimentos`, `requisicoes_lance` (idempotência/frequência) e `avisos_lote` (dou-lhe).
- RLS em todas as tabelas; um tenant nunca vê outro. Compradores leem lotes e lances só pelas views
  `lotes_publicos` e `lances_publicos` (sem reserva, vendedor, líder ou dados pessoais; "Comprador #4821 · Cidade-UF").
- Valores [CONFIGURÁVEL] em `configuracoes_padrao`, sobrescritos por tenant em `configuracoes`.
- `audit_log` automático em lotes, lances, tetos, vendas, usuários etc., mais lances recusados.

**Motor de lances (seção 7)**
- `place_bid(lote, valor, 'manual'|'teto', chave_idempotencia, em_nome_de)`: transação única com trava do lote,
  relógio do servidor, verificação de cadastro, vendedor, prazo, frequência, limite de crédito, incremento,
  tetos automáticos (maior teto vence com segundo + incremento; empate → quem registrou primeiro),
  prorrogação (agora + 3 min) e reagendamento dos avisos de dou-lhe.
- `cancelar_teto`, `encerrar_lote` (idempotente), `responder_consulta_vendedor` (reserva não atingida),
  `agendar_leilao` (encerramento escalonado) e `processar_relogio` (pg_cron, a cada 5 s).
- Estado publicado no Supabase Realtime (canal `lote:<id>`).

**Testes (`npm run test:db`)**: 31 testes, incluindo os 12 casos obrigatórios da seção 7.7.

**App**: Next.js 16 + TypeScript, manifest PWA, identidade visual da seção 12, página inicial do protótipo
lendo `lotes_publicos` com atualização em tempo real (ou dados de demonstração sem Supabase).

## O que a etapa 2 entregou

**Banco (`20261102000004_cadastro.sql`)**
- `iniciar_cadastro(tenant)`: após o código do celular, cria o cadastro (status pendente, papel comprador) ou vincula
  um convite pré-cadastrado pela leiloeira com o mesmo celular.
- `enviar_cadastro(tenant, dados)`: valida nome, CPF/CNPJ (dígitos verificadores), cidade/UF, e-mail, referência,
  documentos (com foto + comprovante; selfie se `cadastro.selfie_obrigatoria`) e aceites; grava consentimentos com
  versão e IP; avisa admin e operadores. Um CPF/CNPJ por leiloeira.
- `analisar_cadastro(usuario, aprovar|pedir_ajuste|recusar, observação)`: só admin; registra em `verificacoes` e
  avisa o usuário.
- Bucket privado `documentos` no Storage (`<tenant>/<usuário>/arquivo`): dono envia e lê, equipe lê, ninguém apaga.

**Telas**: `/entrar` (celular → código), `/cadastro` (4 passos, fotos reduzidas antes do envio), `/conta` (status
com ícone + texto), `/termos` (termos, regras e privacidade — **versão provisória**, redação final do advogado).

**Testes**: 39 no total (8 novos de cadastro).

Até a etapa 4 (painel admin), a aprovação é feita no SQL Editor:
`select analisar_cadastro('<id do usuário>', 'aprovar');` (logado como admin) ou
`update usuarios set status_verificacao = 'verificado' where id = '<id>';`.

## Valores provisórios (aguardam decisão — seção 17)

Marcados com `a_definir = true` em `configuracoes_padrao`:

| Chave | Provisório | Quem decide |
|---|---|---|
| `comissao.comprador_pct` / `comissao.vendedor_pct` | 2% / 2% | Rafael + parceira |
| `comissao.divisao_originador` | 70% originador / 30% plataforma | Rafael + parceira |
| `penalidade.desistencia_multa_pct` | 10% | Parceira |
| `pagamento.prazo_horas` | 48 h | Parceira |
| `lote.tolerancia_quebra_pct` | 3% | Parceira |
| `lote.pesagem_prazo_max_dias` | 15 dias | Parceira |
| `lote.categorias` | lista da seção 6.1 | Parceira |

## Decisões tomadas nesta etapa (confirmar)

- **Usuário por tenant**: cada pessoa tem um registro em `usuarios` por leiloeira (status, limite e código
  público são por leiloeira), ligado ao login do Supabase por `auth_user_id`.
- **Teto igual a lance manual**: se um teto registrado antes for igual ao lance manual de outro, vence o teto
  (regra "vence quem registrou primeiro").
- **Consulta ao vendedor automática** quando a reserva não é atingida (configurável em
  `venda.consulta_vendedor_automatica`).
- **Avisos no WhatsApp**: o protótipo dizia "1 hora e 10 minutos"; segui a matriz da seção 10.2
  (WhatsApp no dou-lhe 3, a 3 minutos do fim).
