# Pregão do Campo — Guia do Sistema

> Plataforma online de leilão de gado **por tempo** (sem transmissão ao vivo), com compradores e vendedores verificados.
> "Pregão do Campo" é nome provisório.
> Versão 1.0 · 31/10/2026 · Autor: Rafael Girotte Polississo

---

## 0. Como usar este guia (instruções para o Claude Code)

- Este arquivo é a **fonte de verdade** do projeto. Leia-o inteiro antes de começar e consulte-o a cada nova etapa.
- Construa **por fases** (seção 15). Não implemente recursos de fases futuras sem pedido explícito, mas modele os dados já pensando nelas (ex.: `tenant_id` desde o início).
- Todo valor marcado como **[CONFIGURÁVEL]** deve ficar em tabela de configuração por leiloeira (tenant), nunca fixo no código.
- Itens marcados como **[A DEFINIR]** dependem de decisão do Rafael ou da parceira. Pergunte antes de assumir.
- O protótipo visual de referência é o arquivo `index.html` (página inicial com lances simulados). Siga seu layout, cores e textos.
- Idioma da interface: português do Brasil. Moeda: BRL. Fuso: `America/Sao_Paulo`.

---

## 1. Visão geral

### 1.1 O que é
Um sistema web onde a leiloeira cadastra lotes de gado, cada lote fica aberto para lances durante um prazo, e compradores previamente verificados disputam o lote pelo celular. Quando o cronômetro zera, o maior lance vence.

### 1.2 Problema que resolve
- Hoje, em leilões transmitidos, os lances chegam desorganizados por WhatsApp e telefone.
- Lotes pequenos e gado geral muitas vezes não cabem na agenda dos leilões presenciais.
- Comprador e vendedor correm risco de calote e de animal diferente do anunciado.

### 1.3 Diferenciais
1. Leilão **por tempo**, com cronômetro e prorrogação automática (antes, ninguém ganhava no último segundo).
2. **Cadastro verificado**: só quem passa pela análise pode dar lance.
3. **Lote vistoriado** por técnico credenciado, com vídeo, pesagem recente e laudo.
4. **Pagamento protegido** (conta garantia): o vendedor só recebe após a entrega conferida.
5. **Avisos no WhatsApp** e notificações no celular.
6. Leve, abre direto do link do WhatsApp, sem precisar baixar app.

### 1.4 Referências de mercado
- **AuctionsPlus** (Austrália): principal referência do formato por tempo, com avaliadores credenciados.
- **MF Leilões** e **LeiloApp** (Brasil): lance online pelo site.
- **Gado Certo** (MT): marketplace com comissão de 2% por lado e frete organizado.
- **Bull Rural**, **Leiloaê**: marketplaces de gado.

---

## 2. Modelo de negócio

O sistema atende **dois modelos**, que convivem no mesmo código:

| Modelo | Como funciona | Receita |
|---|---|---|
| **A. Operação própria** | Rafael + parceira operam os leilões. A parceira traz vendedores e compradores. | Comissão sobre cada venda |
| **B. SaaS white label** | Outras leiloeiras assinam o sistema com marca própria. | Mensalidade + franquia de mensagens |

- O piloto começa no **modelo A**, com uma leiloeira (a parceira).
- O **modelo B** entra na Fase 3. Por isso o banco de dados é **multi-tenant desde o início**.

### 2.1 Comissões (modelo A)
- Comissão do comprador: **[CONFIGURÁVEL]**, padrão sugerido 2%.
- Comissão do vendedor: **[CONFIGURÁVEL]**, padrão sugerido 2%.
- **Divisão por originador** **[CONFIGURÁVEL]**: quem trouxe o lote ou o comprador recebe a maior parte da comissão daquela venda. Exemplo: 70% para a parceira e 30% para a plataforma nos lotes que ela trouxe.
- Todo lote e todo comprador guardam o campo `originador_id`, que alimenta o cálculo.

### 2.2 Planos de mensagens (modelo B)

| | Básico | Profissional | Avançado |
|---|---|---|---|
| Cadastros ativos | até 100 | até 250 | até 500 |
| Mensagens de WhatsApp/mês | 3.000 | 8.000 | 15.000 |
| Notificações push | ilimitadas | ilimitadas | ilimitadas |
| Mensagem excedente | R$ 0,06 | R$ 0,06 | R$ 0,06 |
| **Mensalidade** | **R$ 159** | **R$ 429** | **R$ 789** |

- Base: custo Meta de R$ 0,035 por mensagem de utilidade (tabela de 01/10/2026) + 50%.
- O sistema avisa o administrador ao atingir **80%** da franquia.
- O excedente é cobrado na mensalidade seguinte.
- Os valores ficam em tabela `planos` (editáveis no painel do super admin).

---

## 3. Perfis de usuário

| Perfil | Quem é | O que faz |
|---|---|---|
| **Super admin** | Rafael | Gerencia leiloeiras (tenants), planos, cobrança, configurações globais |
| **Admin da leiloeira** | Parceira / leiloeiro | Aprova cadastros, publica lotes, agenda leilões, acompanha pagamentos, entregas e disputas |
| **Operador** | Equipe da leiloeira | Cadastra lotes, edita vídeos e fotos, atende usuários (permissões limitadas) |
| **Vistoriador** | Técnico credenciado | Vistoria o lote e envia laudo e checklist |
| **Vendedor** | Produtor | Oferece lotes, acompanha lances e recebe pagamento |
| **Comprador** | Produtor / investidor | Dá lances, paga e retira os animais |

- Um mesmo usuário pode ser comprador e vendedor.
- Um usuário pode **delegar acesso** a uma pessoa de confiança (ex.: filho, gerente da fazenda), com registro de quem deu cada lance.

### 3.1 Persona principal: o comprador
- Pecuarista, muitas vezes mais velho, pouca paciência com tecnologia.
- Usa o celular quase só para WhatsApp. Celular simples, com pouca memória e internet rural instável.
- Já compra por WhatsApp e telefone em leilões transmitidos.
- **Implicações de design:** botões grandes (mínimo 44 px, ideal 52 px), pouca digitação, texto legível, carregamento rápido, tudo acessível a partir de um link do WhatsApp.

---

## 4. Plataforma e tecnologia

### 4.1 Formato
- **PWA** (Progressive Web App): site pensado primeiro para celular, que pode ser "instalado" na tela inicial.
- Painel administrativo no mesmo sistema, otimizado para computador.
- Apps nas lojas (Fase 4) gerados do mesmo código com **Capacitor**.

### 4.2 Stack sugerida
| Camada | Tecnologia | Observação |
|---|---|---|
| Front-end | Next.js (React) + TypeScript | PWA com manifest e service worker |
| Banco de dados | Supabase (PostgreSQL) | Plano Pro (US$ 25/mês). O gratuito pausa após 1 semana sem uso |
| Autenticação | Supabase Auth | Login por celular com código (OTP) + e-mail opcional |
| Tempo real | Supabase Realtime | Atualização de lances e cronômetro ao vivo |
| Arquivos | Supabase Storage | Fotos, laudos, documentos |
| Vídeos | Cloudflare Stream | US$ 5/1.000 min armazenados e US$ 1/1.000 min assistidos. No piloto, YouTube não listado é aceitável |
| Funções de servidor | Supabase Edge Functions | Lances, notificações, webhooks |
| Tarefas agendadas | pg_cron ou worker | Abertura e encerramento de lotes, avisos |
| WhatsApp | **WhatsApp Cloud API (Meta), direto** | Sem ferramenta intermediária. Nunca usar API não oficial |
| Push | Web Push / Firebase Cloud Messaging | Gratuito |
| E-mail | Provedor transacional [A DEFINIR] | Recibos e avisos secundários |
| Pagamentos | Provedor com conta garantia e split [A DEFINIR] | Ver seção 9 |
| Hospedagem | Vercel ou Netlify | Plano gratuito no início |
| Domínio | `.com.br` no Registro.br | R$ 40/ano |

### 4.3 Multi-tenant e white label
- Toda tabela de negócio tem `tenant_id`.
- Isolamento por **Row Level Security (RLS)** no Postgres: um tenant nunca vê dados de outro.
- Cada leiloeira tem:
  - subdomínio próprio (`leiloesfulano.pregaodocampo.com.br`) e, opcionalmente, domínio próprio;
  - logo, nome, cores (cor de destaque) e textos de rodapé;
  - configurações próprias (regras de lance, comissões, canais de aviso);
  - número de WhatsApp próprio ou compartilhado [A DEFINIR].

---

## 5. Cadastro e verificação

### 5.1 Fluxo do comprador / vendedor
1. Entra pelo link e informa o celular. Recebe código de confirmação.
2. Preenche: nome completo, CPF ou CNPJ, cidade/UF, inscrição estadual de produtor (quando houver), e-mail.
3. Envia documentos: documento com foto e comprovante de endereço. Selfie opcional [CONFIGURÁVEL].
4. Informa referência bancária ou comercial.
5. Aceita os termos de uso, as regras do leilão e a **autorização para receber avisos no WhatsApp** (opt-in, exigido pela Meta e pela LGPD).
6. Status vira **Pendente**, e o cadastro entra na fila do admin.
7. Consulta automática de CPF/CNPJ em provedor de dados [A DEFINIR]. O resultado aparece como sugestão para o admin.
8. Admin aprova, pede ajuste ou recusa. O usuário é avisado por WhatsApp e push.

### 5.2 Status de cadastro
| Status | Ícone | Pode dar lance? |
|---|---|---|
| Pendente | relógio (cinza) | Não |
| Verificado | escudo com check (verde) | Sim |
| Divergente | alerta (laranja) | Não, aguardando ajuste |
| Recusado | X (cinza escuro) | Não |
| Suspenso | cadeado (laranja) | Não (ex.: desistência de compra) |

### 5.3 Limite de crédito [CONFIGURÁVEL]
- O admin pode definir um **limite de compra** por comprador (valor total em lances vencedores abertos).
- Lance que ultrapassa o limite é bloqueado, com mensagem clara e opção de pedir aumento.

---

## 6. Lotes

### 6.1 Campos obrigatórios
- Título (ex.: "30 garrotes Nelore")
- Categoria: bezerros, bezerras, garrotes, novilhas, vacas, vacas paridas, boi magro, touros [lista CONFIGURÁVEL]
- Raça ou cruzamento
- Sexo
- Quantidade de cabeças
- Peso médio + **data da pesagem** (pesagem recente obrigatória, prazo máximo [CONFIGURÁVEL])
- Faixa de idade (ex.: 12 a 14 meses)
- Sanidade: vacinas, vermifugação, observações
- Cidade/UF de origem
- Condições de retirada: prazo (padrão 5 dias), frete por conta de quem
- Tolerância de quebra de peso no transporte (%) [CONFIGURÁVEL]
- **Vídeo** do lote (obrigatório) e fotos (mínimo 3)
- **Laudo de vistoria** (PDF) do técnico credenciado
- Preço inicial por cabeça
- Preço de reserva por cabeça (opcional, não exibido ao comprador)
- Vendedor (oculto para compradores até o arremate)
- Originador (quem trouxe o lote)

### 6.2 Ciclo de vida do lote
```
rascunho → em_vistoria → aprovado → agendado → aberto → encerrado
encerrado → vendido | nao_vendido (reserva não atingida ou sem lances)
vendido → aguardando_pagamento → pago_em_garantia → em_transporte → entregue
entregue → conferido → pagamento_liberado → concluido
entregue → em_disputa → (resolvido) → pagamento_liberado | cancelado
qualquer estado antes de "aberto" → cancelado
```

### 6.3 Lote não vendido
- Se o preço de reserva não for atingido, o admin pode **perguntar ao vendedor** se aceita o maior lance (prazo [CONFIGURÁVEL], ex.: 24 h).
- O comprador do maior lance é avisado de que o lote está "aguardando confirmação do vendedor".

---

## 7. Regras do leilão (motor de lances)

> Esta é a parte mais crítica. Toda validação acontece **no servidor**, com o **horário do servidor**. O cronômetro do navegador é só visual.

### 7.1 Regras gerais
| Regra | Valor padrão |
|---|---|
| Lance é sempre **por cabeça** | — |
| Total do lote = lance × quantidade (exibido sempre) | — |
| Incremento mínimo | R$ 20/cabeça [CONFIGURÁVEL] |
| Botões de lance rápido | + R$ 20, + R$ 50, + R$ 100 [CONFIGURÁVEL] |
| Janela de prorrogação | 3 minutos [CONFIGURÁVEL] |
| Prorrogação | Lance com menos de 3 min restantes leva o fim para **agora + 3 min** |
| Empate | Vence o lance registrado primeiro |
| Lance é compromisso | Lance vencedor obriga a compra |
| Multa por desistência | 10% do valor do lote + suspensão [CONFIGURÁVEL] |

### 7.2 Encerramento escalonado
- Um leilão (evento) agrupa vários lotes.
- Os lotes fecham **em sequência**, com intervalo de [CONFIGURÁVEL, padrão 2 min] entre eles. Isso mantém a atenção dos compradores e evita que todos fechem ao mesmo tempo.
- A prorrogação de um lote **não** empurra os seguintes.

### 7.3 Lance automático (teto)
- O comprador informa o **valor máximo por cabeça** que aceita pagar.
- O sistema cobre automaticamente os lances dos outros, de incremento em incremento, até esse teto.
- O teto é **secreto**: ninguém vê o valor, só o lance resultante.
- Dois tetos concorrentes: o maior teto vence com o valor de (segundo maior teto + incremento), limitado ao próprio teto. Empate de teto: vence quem registrou primeiro.
- O comprador pode aumentar o teto a qualquer momento e cancelar enquanto não for o líder.
- No histórico, o lance aparece como "Você · automático" para o dono e como lance comum para os demais.

### 7.4 Anonimato
- Comprador aparece como `Comprador #4821 · Cidade-UF`.
- Vendedor aparece como `Fazenda #128 · Cidade-UF`, ou nome da fazenda se o vendedor autorizar [CONFIGURÁVEL].
- Nome, telefone e endereço só são liberados **entre as partes, após o pagamento cair na conta garantia**.

### 7.5 Algoritmo de lance (servidor)
Função única e transacional, ex.: `place_bid(lot_id, user_id, valor_por_cabeca, tipo)`, onde `tipo` é `manual` ou `teto`.

```
INÍCIO TRANSAÇÃO
  lote = SELECT ... FROM lotes WHERE id = lot_id FOR UPDATE   -- trava a linha
  agora = now()  -- horário do servidor

  validar:
    lote.status == 'aberto'
    agora < lote.termina_em
    usuário verificado, não suspenso, não é o vendedor do lote
    valor >= lote.lance_atual + incremento (ou >= preço inicial se não houver lances)
    limite de crédito do usuário não ultrapassado
    idempotência: mesma chave de requisição não gera dois lances

  se tipo == 'teto': registrar/atualizar teto do usuário
  registrar lance
  resolver tetos automáticos concorrentes (seção 7.3)
  atualizar lote.lance_atual, lote.lider_id, lote.qtd_lances

  se (lote.termina_em - agora) < janela_prorrogacao:
      lote.termina_em = agora + janela_prorrogacao
      lote.prorrogado = true
      reagendar avisos de "dou-lhe" deste lote   -- ver seção 10.4

  gravar evento em audit_log
FIM TRANSAÇÃO

publicar no canal realtime do lote: novo estado
disparar evento "lance_coberto" para o líder anterior (se mudou)
```

- Limitar a frequência de lances por usuário (ex.: no máximo 1 por segundo por lote).
- Antes de enviar, o app mostra uma **confirmação**: "Confirmar lance de R$ 2.930/cab · total R$ 87.900".

### 7.6 Encerramento do lote
- Um worker verifica lotes com `termina_em <= now()` a cada poucos segundos.
- O encerramento é **idempotente** (rodar duas vezes não gera dois vencedores).
- Qualquer lance que chegue após `termina_em` é recusado, mesmo que o worker ainda não tenha rodado.
- No encerramento: definir vendido ou não vendido, criar o pedido de venda, avisar o vencedor, o vendedor e os participantes.

### 7.7 Casos de teste obrigatórios
1. Lance abaixo do mínimo é recusado.
2. Lance após o horário de término é recusado.
3. Dois lances simultâneos no mesmo valor: só um é aceito, o primeiro.
4. Lance com 2 min restantes leva o término para agora + 3 min.
5. Lance com 5 min restantes **não** altera o término.
6. Teto de A (3.100) contra lance manual de B (2.950): A passa a liderar com 2.970.
7. Tetos de A (3.100) e B (3.000): A lidera com 3.020.
8. Tetos iguais: vence quem registrou primeiro.
9. Vendedor não consegue dar lance no próprio lote.
10. Usuário pendente ou suspenso não consegue dar lance.
11. Encerramento executado duas vezes gera um único pedido.
12. Reserva não atingida resulta em "não vendido", com consulta ao vendedor.

---

## 8. Comunicação entre as partes (anti-desvio)

Objetivo: evitar que comprador e vendedor fechem negócio por fora depois de se conhecerem pela plataforma.

- **Sem chat livre.** Perguntas sobre o lote são enviadas à leiloeira, que responde publicamente no lote (perguntas e respostas visíveis a todos).
- Bloqueio automático de telefone, e-mail, links e @ nas mensagens.
- Contato direto liberado só após o pagamento em garantia.
- **Registro completo**: todo lote, lance, alteração e cancelamento fica no `audit_log`, visível no painel do admin e do super admin.
- **Alerta de padrão suspeito** (Fase 2): lote cancelado ou retirado após receber lances, e mesmo vendedor e comprador aparecendo juntos depois. Aparece no painel com ícone de alerta e ações sugeridas.
- **Termos de uso** com cláusula de exclusividade: venda a comprador conhecido pela plataforma num prazo de [CONFIGURÁVEL, ex.: 6 meses] continua devendo comissão + multa. (Redação final por advogado.)

---

## 9. Pagamento, entrega e conferência

### 9.1 Piloto (Fase 1)
- Pagamento **à vista**, por PIX ou transferência, fora do sistema.
- O admin confirma o recebimento manualmente no painel ("Marcar como pago").

### 9.2 Conta garantia (Fase 2)
- Provedor de pagamento com **conta garantia e divisão automática (split)** [A DEFINIR — avaliar opções do mercado].
- Fluxo:
  1. Lote arrematado: o comprador recebe a cobrança (lote + comissão do comprador). Prazo [CONFIGURÁVEL, ex.: 48 h].
  2. O pagamento fica retido.
  3. Liberação após a conferência (ou após o fim do prazo de contestação sem reclamação).
  4. Split automático: vendedor (valor − comissão do vendedor), leiloeira, plataforma, originador.
- Pagamento não feito no prazo: aviso, depois multa e suspensão, e o lote é oferecido ao segundo colocado [CONFIGURÁVEL].
- **Parcelamento** [A DEFINIR]: hoje a leiloeira garante. Avaliar parceria com banco ou fintech de crédito rural.

### 9.3 Documentos da venda
- **GTA** (Guia de Trânsito Animal): emitida pelo vendedor no órgão estadual. Upload obrigatório no sistema antes da retirada.
- Nota fiscal de produtor: upload pelo vendedor.
- Recibo / termo de arremate gerado automaticamente em PDF.

### 9.4 Entrega e conferência
1. O vendedor registra a pesagem de saída (foto da balança).
2. O comprador confirma o recebimento e registra a contagem e a pesagem de chegada.
3. A diferença de peso dentro da tolerância de quebra é aceita automaticamente.
4. **Prazo de contestação: 48 h** após o recebimento [CONFIGURÁVEL].
5. Contestação: o comprador descreve o problema e envia fotos ou vídeo. O lote vai para **em_disputa**, e o admin media.
6. Resolução da disputa: liberação total, desconto parcial ou cancelamento (devolução dos animais).

---

## 10. Notificações

### 10.1 Canais
| Canal | Custo | Uso |
|---|---|---|
| WhatsApp (Cloud API, categoria **utilidade**) | R$ 0,035/msg (desconta da franquia) | Avisos críticos |
| Push (navegador/celular) | Gratuito | Avisos frequentes |
| E-mail | Quase zero | Recibos, documentos, resumos |
| Dentro do app (sininho) | Gratuito | Todos os avisos |

### 10.2 Matriz de avisos (padrão, [CONFIGURÁVEL] por tenant)
| Evento | Quem recebe | WhatsApp | Push | E-mail |
|---|---|---|---|---|
| Cadastro aprovado / ajuste / recusado | Usuário | ✓ | ✓ | ✓ |
| Leilão abrindo (novo catálogo) | Inscritos no aviso | opcional | ✓ | ✓ |
| Dou-lhe 1 — faltam 10 min | Quem deu lance + quem acompanha o lote | — | ✓ | — |
| Dou-lhe 2 — faltam 5 min | Quem deu lance + quem acompanha | — | ✓ | — |
| Dou-lhe 3 — faltam 3 min | **Quem deu lance** | ✓ | ✓ | — |
| Dou-lhe 3 — faltam 3 min | Só quem acompanha | — | ✓ | — |
| Seu lance foi coberto | Líder anterior | ✓ | ✓ | — |
| Lance automático chegou ao teto | Dono do teto | ✓ | ✓ | — |
| Você arrematou | Vencedor | ✓ | ✓ | ✓ |
| Seu lote foi vendido / não vendido | Vendedor | ✓ | ✓ | ✓ |
| Pagamento pendente / confirmado | Comprador / vendedor | ✓ | ✓ | ✓ |
| Retirada, entrega, contestação | Partes envolvidas | ✓ | ✓ | ✓ |
| Franquia de mensagens em 80% | Admin | — | ✓ | ✓ |

### 10.3 Controle de custo
- **Agrupar "lance coberto"**: se o mesmo usuário for coberto várias vezes em pouco tempo (ex.: disputa contra teto), enviar **um único** WhatsApp a cada [CONFIGURÁVEL, ex.: 2 min] por lote, com o valor mais recente. Push pode ir sempre.
- **Não enviar** WhatsApp de "coberto" se o usuário estiver com o lote aberto na tela (presença via realtime) [CONFIGURÁVEL].
- O usuário escolhe nas preferências quais avisos quer por WhatsApp (sempre respeitando o opt-out).
- Contabilizar toda mensagem enviada em `uso_mensagens` (por tenant e por mês) para a franquia e o excedente.
- Ao estourar a franquia: continuar enviando e cobrar o excedente [CONFIGURÁVEL] ou passar a enviar só push.

### 10.4 Agendamento dos avisos de "dou-lhe"
- Ao abrir o lote, agendar os avisos para `termina_em − 10 min`, `− 5 min` e `− 3 min`.
- **Quando o lote é prorrogado**, cancelar e reagendar os avisos pendentes com base no novo `termina_em`.
- Não reenviar um aviso que já foi enviado para o mesmo usuário e lote (deduplicação por chave `usuario + lote + tipo`).
- Se o lote for prorrogado com menos de 3 min, não repetir o dou-lhe 3 a cada prorrogação. Enviar no máximo [CONFIGURÁVEL, ex.: 2] avisos de prorrogação por lote.

### 10.5 Modelos de mensagem do WhatsApp (utilidade)
Os modelos precisam ser **informativos**, sem tom de propaganda. Se a Meta classificar como marketing, o custo sobe cerca de 9 vezes.

- **Lance coberto:** "Seu lance no Lote {{1}} ({{2}}) foi coberto. Lance atual: {{3}}/cab. Termina às {{4}}. Para cobrir: {{5}}"
- **Dou-lhe 3:** "Faltam 3 minutos para o fim do Lote {{1}} ({{2}}). Lance atual: {{3}}/cab. Você está {{4}}. Acesse: {{5}}"
- **Arremate:** "Você arrematou o Lote {{1}} ({{2}}) por {{3}}/cab, total {{4}}. Instruções de pagamento: {{5}}"
- **Abertura:** "O leilão {{1}} que você pediu para acompanhar está aberto. {{2}} lotes, encerramento a partir de {{3}}. Catálogo: {{4}}"

Os links levam direto ao lote, já autenticado quando possível (link mágico com validade curta).

### 10.6 Regras da Meta
- Opt-in obrigatório no cadastro; opt-out por resposta "SAIR" ou nas preferências.
- Conta nova envia para até 250 pessoas diferentes por dia. Após verificação da empresa, sobe para 2.000. **Verificar a empresa antes do primeiro leilão com mais de 250 cadastros.**
- Guardar o identificador do usuário no WhatsApp (BSUID) além do número.

---

## 11. Telas

### 11.1 Comprador / vendedor (celular primeiro)
1. **Página inicial** (protótipo `index.html`): cabeçalho com status do cadastro, explicação em 3 passos, lote em destaque "Encerrando agora", grade de leilões abertos com filtros por categoria, regras do lance.
2. **Página do lote**: vídeo, fotos, laudo, ficha técnica, cronômetro, lance atual por cabeça e total, botões de lance rápido, lance automático, histórico de lances, perguntas e respostas.
3. **Meus lances**: lotes em que dei lance, com status (liderando, superado, arrematado, encerrado) e ação sugerida ("Cobrir agora", "Ver lote").
4. **Minhas compras**: pagamento, documentos, retirada, conferência e contestação.
5. **Meus lotes (vendedor)**: lotes cadastrados, status, lances recebidos, documentos pendentes.
6. **Cadastrar lote (vendedor)**: formulário guiado em etapas, com envio de vídeo pelo celular.
7. **Cadastro e perfil**: dados, documentos, status da verificação, pessoas com acesso delegado.
8. **Preferências de aviso**: quais avisos por WhatsApp, push e e-mail.
9. **Agenda de leilões**: próximos leilões com botão "Me avise quando abrir".

### 11.2 Painel do admin (computador primeiro)
Todo item de fila mostra um **ícone de status** e **botões de ação sugerida**, para o admin decidir com um clique.

| Tela | Status exibidos | Ações sugeridas |
|---|---|---|
| Fila de cadastros | Verificado pela consulta / Divergente / Pendente | Aprovar · Pedir documento · Recusar |
| Lotes em preparação | Falta vídeo / Falta laudo / Pronto | Cobrar vendedor · Enviar ao vistoriador · Aprovar |
| Leilões | Agendado / Aberto / Encerrado | Editar · Pausar lote · Ver ao vivo |
| Ao vivo | Liderando, nº de lances, prorrogado | Pausar · Cancelar lote (com motivo) |
| Pós-venda | Aguardando pagamento / Pago / Em atraso | Reenviar cobrança · Confirmar pagamento · Oferecer ao 2º colocado |
| Entregas | Em transporte / Entregue / Em disputa | Ver documentos · Mediar · Liberar pagamento |
| Alertas | Padrão suspeito / Limite de crédito | Investigar · Suspender · Ignorar |
| Mensagens | % da franquia usada | Ver consumo · Ajustar canais |
| Relatórios | — | Exportar CSV/PDF |
| Configurações | — | Regras de lance, comissões, canais, marca |

### 11.3 Vistoriador
- Lista de lotes atribuídos, checklist de vistoria, upload de fotos e laudo, assinatura (aceite com data, hora e localização).

### 11.4 Super admin (Rafael)
- Leiloeiras (tenants): criar, configurar marca e domínio, plano, suspender.
- Planos e cobrança das mensalidades e do excedente.
- Consumo de mensagens por tenant.
- Auditoria global.

---

## 12. Identidade visual (do protótipo)

| Token | Cor | Uso |
|---|---|---|
| Fundo | `#F3F4F0` | Fundo da página |
| Card | `#FFFFFF` | Cartões |
| Linha | `#DCDFD8` | Bordas |
| Texto | `#1A1F1C` | Texto principal |
| Texto 2 | `#4A524D` | Texto secundário |
| Destaque | `#1F3D2B` | Botões principais (cor trocável por tenant) |
| Verde | `#1F6B3A` / fundo `#E4F0E7` | Liderando, verificado |
| Laranja | `#8A3B08` / fundo `#FCE9DC` | Superado, urgente, prorrogado |
| Cinza | `#3E4741` / fundo `#ECEEEA` | Encerrado |

- Fontes: **Archivo** (títulos, números e cronômetro) e **Inter** (texto).
- Números do cronômetro com `font-variant-numeric: tabular-nums`.
- Ícones de traço (SVG), sem emoji.
- Botões com no mínimo 44 px de altura (lance: 52 px).
- Status nunca indicado só pela cor: sempre ícone + texto.
- Contraste mínimo de 4,5:1.

---

## 13. Modelo de dados (resumo)

Todas as tabelas de negócio têm `id`, `tenant_id`, `criado_em` e `atualizado_em`.

| Tabela | Campos principais |
|---|---|
| `tenants` | nome, subdominio, dominio, logo_url, cor_destaque, plano_id, status |
| `configuracoes` | tenant_id, chave, valor (regras de lance, comissões, canais etc.) |
| `planos` | nome, limite_cadastros, franquia_msgs, preco_mensal, preco_excedente |
| `usuarios` | nome, cpf_cnpj, celular, email, cidade, uf, inscricao_estadual, status_verificacao, limite_credito, optin_whatsapp, bsuid, originador_id |
| `papeis_usuario` | usuario_id, tenant_id, papel (admin, operador, vistoriador, comprador, vendedor) |
| `acessos_delegados` | titular_id, delegado_id, permissoes |
| `verificacoes` | usuario_id, tipo, resultado, dados_consulta, analisado_por, observacao |
| `documentos` | dono_id, tipo, arquivo_url, status |
| `fazendas` | vendedor_id, nome, cidade, uf, apelido_publico |
| `leiloes` | titulo, abre_em, primeiro_fechamento_em, intervalo_fechamento, status |
| `lotes` | leilao_id, vendedor_id, fazenda_id, originador_id, numero, titulo, categoria, raca, sexo, quantidade, peso_medio, data_pesagem, idade_min, idade_max, sanidade, cidade, uf, retirada_prazo, frete, tolerancia_quebra, preco_inicial, preco_reserva, incremento, lance_atual, lider_id, qtd_lances, abre_em, termina_em, termina_em_original, prorrogado, status |
| `midias_lote` | lote_id, tipo (video, foto, laudo), url, ordem |
| `vistorias` | lote_id, vistoriador_id, checklist (json), laudo_url, aprovado, assinado_em |
| `lances` | lote_id, usuario_id, delegado_id, valor_por_cabeca, tipo (manual, automatico), chave_idempotencia, criado_em |
| `tetos` | lote_id, usuario_id, valor_maximo, ativo |
| `acompanhamentos` | lote_id ou leilao_id, usuario_id (quem pediu aviso) |
| `perguntas` | lote_id, usuario_id, pergunta, resposta, respondido_por, publica |
| `vendas` | lote_id, comprador_id, vendedor_id, valor_por_cabeca, quantidade, total, comissao_comprador, comissao_vendedor, status |
| `pagamentos` | venda_id, provedor, id_externo, valor, status, pago_em, liberado_em |
| `repasses` | pagamento_id, beneficiario (vendedor, leiloeira, plataforma, originador), valor, status |
| `entregas` | venda_id, pesagem_saida, pesagem_chegada, cabecas_recebidas, gta_url, nf_url, recebido_em |
| `disputas` | venda_id, aberta_por, motivo, evidencias, status, resolucao |
| `penalidades` | usuario_id, venda_id, tipo, valor, status |
| `notificacoes` | usuario_id, lote_id, tipo, canal, status, chave_dedup, agendado_para, enviado_em |
| `uso_mensagens` | tenant_id, mes, quantidade, excedente |
| `audit_log` | tenant_id, ator_id, acao, entidade, entidade_id, dados_antes, dados_depois, ip, criado_em |

---

## 14. Segurança, LGPD e legal

- **RLS** em todas as tabelas. Dados pessoais (CPF, telefone, endereço) nunca expostos a outros usuários antes da liberação.
- Documentos em armazenamento privado com links temporários.
- Dados sensíveis criptografados em repouso quando possível.
- Registro de consentimentos (termos, opt-in de WhatsApp) com data e versão.
- Direito de exclusão e exportação de dados (LGPD), respeitando o que precisa ser guardado por obrigação legal e fiscal.
- Backup diário do banco.
- Proteção contra abuso: limite de requisições, captcha no cadastro.
- **[A DEFINIR] Questão legal:** confirmar com advogado se a operação exige **leiloeiro rural oficial** ou pode funcionar como intermediação/marketplace. Se a parceira tiver registro de leiloeira, isso pode resolver.
- Termos de uso, regras do leilão, política de privacidade e contrato de parceria redigidos por advogado.

---

## 15. Fases de desenvolvimento

### Fase 0 — Protótipo ✓
- Página inicial com lances simulados (`index.html`).

### Fase 1 — MVP do piloto (uma leiloeira)
Objetivo: um leilão real com 3 a 5 lotes e 20 a 30 compradores convidados.
- Login por celular, cadastro, envio de documentos, aprovação manual.
- Cadastro de lotes pelo admin/operador (vídeo, fotos, laudo em PDF).
- Leilão por tempo: motor de lances completo (seção 7), prorrogação, lance automático, encerramento escalonado, tempo real.
- Páginas: inicial, lote, meus lances, minhas compras (simples), perfil, preferências.
- Notificações: push + WhatsApp (lance coberto, dou-lhe 3, arremate, cadastro aprovado).
- Painel admin: fila de cadastros, lotes, leilões, ao vivo, pós-venda com confirmação manual de pagamento.
- `audit_log` e anonimato.
- Banco já multi-tenant, com um único tenant ativo.

### Fase 2 — Operação completa
- Conta garantia e split de pagamento.
- Entrega, conferência, contestação e disputas.
- Comissões e repasse por originador.
- Perfil de vistoriador.
- Cadastro de lotes pelo próprio vendedor.
- Limite de crédito, penalidades, oferta ao segundo colocado.
- Perguntas e respostas no lote.
- Relatórios (faturamento, média por categoria, nº de animais, compradores ativos).
- Alertas de padrão suspeito.

### Fase 3 — SaaS white label
- Painel do super admin.
- Onboarding de novas leiloeiras: marca, subdomínio, configurações.
- Planos, franquias de mensagens, cobrança de mensalidade e excedente.
- Aviso de 80% da franquia.

### Fase 4 — Expansão
- Apps nas lojas via Capacitor (Google: US$ 25 uma vez; Apple: US$ 99/ano).
- Parcelamento e crédito rural com parceiro financeiro.
- Integrações com gestão de rebanho.

---

## 16. Custos estimados

### 16.1 Fixos mensais (dólar ~R$ 5,40)
| Item | Piloto | Operação (até 500 usuários) |
|---|---|---|
| Supabase Pro | R$ 135 | R$ 135 |
| Hospedagem do site | R$ 0 | R$ 0–110 |
| Vídeos (Cloudflare Stream) | R$ 0–30 | ~R$ 80 |
| Domínio | R$ 3 | R$ 3 |
| E-mail profissional | — | R$ 30–60 |
| Contador | — | R$ 300–600 |
| **Total** | **~R$ 140–200** | **~R$ 550–990** |

### 16.2 Únicos
- Advogado (termos, regras, LGPD, acordo de sócios): estimativa de R$ 2.000 a R$ 6.000.
- Abertura de empresa: a consultar com contador.

### 16.3 Variáveis
- WhatsApp: R$ 0,035/msg (coberto pelos planos).
- Verificação de CPF/CNPJ: por consulta.
- Pagamento e conta garantia: % por transação.

---

## 17. Pontos em aberto

| # | Questão | Quem decide |
|---|---|---|
| 1 | Exigência de leiloeiro rural oficial | Advogado + parceira |
| 2 | Provedor de pagamento com conta garantia e split | Rafael |
| 3 | Provedor de consulta de CPF/CNPJ | Rafael |
| 4 | Como tratar parcelamento | Parceira + parceiro financeiro |
| 5 | Comissões padrão e divisão com a parceira | Rafael + parceira |
| 6 | Valor da multa por desistência e prazos de pagamento | Parceira |
| 7 | Tolerância de quebra de peso padrão | Parceira |
| 8 | Número de WhatsApp único ou por leiloeira | Rafael |
| 9 | Nome definitivo e domínio | Rafael |
| 10 | Categorias de gado e campos extras por categoria (ex.: leite) | Parceira |
