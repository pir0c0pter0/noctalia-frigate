# Plano: eventos da campainha

## Objetivo

Receber o evento físico da campainha e abrir o painel sem depender da amostragem
periódica do estado. Preservar a configuração, o Secret Service e o fluxo de
abertura atuais. Os registros disponíveis não comprovam a causa das falhas.

## Opções e decisão provisória

- **ONVIF PullPoint:** criar uma assinatura e manter uma requisição HTTP
  aguardando eventos; reiniciá-la assim que responder. É long polling de
  eventos, não push puro, mas evita a lacuna da consulta de estado. Não exige
  abrir uma porta de entrada nem um serviço externo. É a opção a investigar
  primeiro, condicionada ao teste com a campainha real.
- **ONVIF push ou TCP push:** poderiam entregar eventos diretamente, mas não há
  API documentada no runtime para servidor HTTP ou socket TCP arbitrário. Um
  processo auxiliar ou mudança no Noctalia exigiria outra avaliação.
- **Consulta atual:** manter como contingência somente enquanto a assinatura
  não estiver operacional; indicar claramente que é modo de contingência e que
  pode perder toques. Não executar os dois caminhos simultaneamente.

O equipamento aceitou WS-Security UsernameToken PasswordDigest no SOAP com HTTP
nativo, sem Digest HTTP. A assinatura e o PullMessages foram confirmados no
equipamento; a recepção de um toque físico ainda exige teste.

## Etapas

1. **Provar a viabilidade antes de alterar o produto.** Identificar versão do
   Noctalia instalado e limites reais de `http`, autenticação suportada,
   timeout, formato e tamanho das respostas. Com a campainha real, verificar
   ONVIF habilitado, descoberta do serviço de eventos, autenticação e criação
   de assinatura. Observar um toque físico e uma reconexão, sem registrar
   endereços, credenciais, tokens ou corpo de respostas em logs. Confirmar o
   tópico e o valor do evento recebido. Se algum requisito falhar, interromper
   a implementação e documentar a limitação; não presumir suporte.
2. **Implementar a assinatura, se comprovada.** Em `Doorbell.luau`, reutilizar
   as credenciais atuais apenas em memória; criar a assinatura, enviar uma
   única requisição `PullMessages` por vez, renovar antes do vencimento e
   recriar após falha com espera limitada. Validar endereço retornado pelo
   dispositivo para evitar envio de credenciais a outro host. Interpretar SOAP
   e XML com um parser seguro disponível no runtime; não usar padrões frágeis
   sobre XML arbitrário. Caso não exista parser adequado, reavaliar a solução
   antes de adicionar dependência ou processo auxiliar.
3. **Integrar eventos ao painel.** Filtrar exclusivamente o evento real de
   botão e sua transição ativa; deduplicar estado repetido e mensagens iniciais,
   sem suprimir um novo toque válido. Continuar enviando `command: ring` para
   `Main.luau`. Invalidar callbacks antigos em troca de endereço, retry, reload
   e saída. Encerrar ou cancelar assinaturas e requisições quando possível.
4. **Contingência e observabilidade.** Usar a consulta existente somente quando
   a assinatura não estiver operacional, com troca explícita entre modos e sem
   abertura duplicada durante a transição. Publicar status no painel e registrar
   apenas mudanças de estado, falhas categorizadas e eventos detectados, sem
   dados sensíveis. Atualizar traduções e `README.md` com os requisitos ONVIF e
   limitações de reconexão; não prometer entrega durante desconexões.
5. **Verificar.** Ampliar `tests/doorbell.lua` com respostas observadas e
   sanitizadas: evento de botão, evento irrelevante, repetição, mensagens de
   estado inicial, autenticação, vencimento, timeout, resposta inválida,
   reconexão, endereço não confiável, troca de modo e callbacks obsoletos.
   Validar integração em `tests/service.lua`, rodar os testes de interface e
   lint existentes. Por fim, testar repetidos toques físicos, suspensão/rede,
   reconexão, troca de configuração e tempo de resposta no Noctalia real.

## Referências

- Runtime Noctalia: https://docs.noctalia.dev/noctalia/plugins/development/runtime-api/
- Fluxo PullPoint ONVIF: https://developer.onvif.org/pub/core/Core_2.00.pdf
- Métodos de eventos Reolink: https://www.home-assistant.io/integrations/reolink/

## Verificação de viabilidade em 2026-10-28

- Noctalia instalado: 5.3.0. A campainha respondeu a `GetCapabilities` e
  anunciou um serviço de eventos no mesmo host. A criação da assinatura
  respondeu HTTP 200 com autenticação Digest; com Basic retornou HTTP 401 e
  desafio Digest.
- A API documentada do Noctalia expõe credenciais HTTP Basic e não expõe parser
  XML. O código público consultado do cliente HTTP configura Basic; não foi
  confirmada uma API nativa para Digest. `PullMessages` no teste preliminar
  retornou SOAP Fault/HTTP 400, portanto não confirmou recebimento de eventos.
- A investigação posterior confirmou que WS-Security PasswordDigest no corpo
  SOAP permite autenticar sem Digest HTTP. PullMessages e Unsubscribe funcionam
  com os cabeçalhos SOAP WS-Addressing Action e To. A resposta inclui estados
  `Initialized`, que não devem ser tratados como um toque.
- Implementar SHA-1 e Base64 em Luau, nonce obtido do UUID aleatório do kernel,
  parser XML com limites e proibição de DTD, PullMessages com timeout inferior
  ao limite de 30 segundos do cliente, validação dos destinos e renovação da
  assinatura. Rejeitar falhas sem registrar segredos ou respostas completas.

## Resultado da implementação

O serviço ONVIF foi ativado no Noctalia em execução. Em um teste físico, o log
registrou a detecção de um toque e a abertura do painel às 16:39:02, além de
outro toque detectado às 16:39:22. A leitura assíncrona do UUID falhou no
Noctalia 5.3 em execução; a leitura síncrona do arquivo do kernel funcionou.
Foram revisados segurança, protocolo, XML, ciclo de vida e confiabilidade.
Os testes da campainha, do serviço, da interface, dos módulos de autenticação
e XML, das credenciais e o lint passaram. A resposta HTTP é acumulada pelo
Noctalia antes da verificação de tamanho do parser; a renovação prolongada da
assinatura ainda requer observação adicional.
