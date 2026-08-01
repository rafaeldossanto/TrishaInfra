# trilha-infra

Infraestrutura do Trilha: compose de producao com os 5 microservicos
(imagens do ghcr.io) + Postgres, Redis, MinIO, Mosquitto e Zeebe, o workflow
de deploy via SSH, e um compose de desenvolvimento com so a infra de apoio.

## Desenvolvimento local

```
docker compose -f docker-compose.dev.yml up -d
```

Sobe **Redis** (6379), **MinIO** (9000 + console 9001), **Mosquitto** (1883,
anonimo) e **Zeebe** (26500). O **Postgres continua nativo** na 5432, fora
deste compose; os servicos Spring rodam na IDE ou com `./gradlew bootRun`.

O Zeebe e obrigatorio para o cadastro por e-mail: sem ele o `POST /usuario` do
Cadastro falha por design (o `RegistrationService` desfaz o registro quando nao
consegue iniciar o processo). O `dev-login` nao passa por ele.

**Estado atual: DORMENTE.** Nenhuma VPS contratada; o pipeline de cada
servico ja publica imagens no ghcr.io a cada merge na master, e este repo
deixa o deploy pronto para quando existir servidor.

## Arquitetura do deploy

```
push na master (cada repo) ──> CI: testes ──> imagem ghcr.io/rafaeldossanto/trilha-<svc>:latest
                                                        │
deploy.yml (clique manual) ──> guard de CI ──> SSH na VPS ──> compose pull + up -d ◄┘
                                    │
                                    └─ CI vermelho/incompleto: bloqueia, nada sai daqui
```

O **guard de CI** existe porque o deploy mentia. Quando o CI de um servico
quebra, o job que publica a imagem nao roda e a tag `:latest` continua apontando
para o commit anterior — o `compose pull` re-subia a versao velha e o workflow
terminava **verde**, como se a correcao tivesse ido para producao. Antes de
tocar no servidor, o deploy agora confere na API do GitHub o ultimo run de
`push` do `ci.yml` na master de cada servico alvo e bloqueia se ele quebrou,
ainda esta rodando, ou nem existe para o commit atual. Na duvida (API fora, rate
limit) ele **bloqueia**: falha fechada.

Ao final, o Step Summary do run lista qual commit de cada servico subiu — e como
o compose so diz `:latest`, esse resumo e hoje o unico registro de qual versao
esta em producao.

> O mapa servico -> repo vive no proprio `deploy.yml`. O BFF e o repo
> **`TrishaBff`**; existe um `rafaeldossanto/BFF` de outro projeto, e o GitHub
> resolve nome de repo sem diferenciar maiuscula — um mapa desatualizado
> validaria o CI do projeto errado e liberaria deploy quebrado.

O front web nao vive aqui: ele e publicado no **Firebase Hosting** a partir do
repo `TrishaWeb` (workflow `Deploy web`). Esta stack serve so a API.

- Quem recebe trafego externo e o **Caddy** (80/443), que faz TLS automatico e
  roteia por path. Nenhum servico publica porta — nem o BFF. A unica outra porta
  aberta e a do **Mosquitto (1883)**, para os devices publicarem GPS.
  - `/arquivo/*` → **midia:8083** (upload e leitura do binario nao passam pelo BFF)
  - `/ws-localizacao/*` → **loc:8082** (STOMP/SockJS do "assistir ao vivo")
  - todo o resto → **bff:8090**
- O Postgres e a imagem **`postgis/postgis`**, nao o `postgres` puro: o `loc`
  roda `CREATE EXTENSION postgis` e cria indice GiST. Com a imagem sem a
  extensao o Flyway aborta e o servico entra em crash loop.
- Sao 3 bancos: **`trisha`** (compartilhado por Cadastro e APP),
  `trilha_localizacao` e `trilha_midia`.
  - O compartilhamento e proposital: a entidade `User` do APP e uma view
    read-only (`@Immutable`) da tabela `usuario` que o Cadastro escreve. Com
    bancos separados essa copia nasce vazia e a busca de usuario, o seguir por
    codigo e o nome do autor no feed param de funcionar.
  - Cada servico tem historico proprio do Flyway no mesmo schema (o APP usa
    `spring.flyway.table=flyway_schema_history_app`), senao as sequencias de
    versao dos dois colidiriam.
- O Cadastro **aborta o boot** em prod sem a chave RSA montada em
  `./keys/jwt-private.pem` (comportamento intencional).
- Em prod `DDL_AUTO=validate`: o schema e criado **inteiramente pelo Flyway**.
  Cada servico tem uma migration de schema base (`V8` no APP, `V4` no Cadastro,
  `V3` na midia, `V4` no loc) que faz um banco vazio subir do zero.
- O **Zeebe** roda no compose e o Cadastro aponta para ele via
  `ZEEBE_GATEWAY_ADDRESS`. Sem Zeebe saudavel o cadastro nao funciona.
- O Mosquitto de prod **proibe anonimo**: o loc autentica com
  `MQTT_USERNAME`/`MQTT_PASSWORD`, que precisam existir no `passwd`/`acl`.
- O front web so consegue chamar a API se `CORS_ALLOWED_ORIGINS` tiver o
  dominio publico dele (vale para o BFF e para a midia, que recebe upload direto).
- `MIDIA_PUBLIC_URL` precisa ser o dominio da API: e com ele que o servico de
  Midia monta a URL do binario (`/arquivo/{id}/conteudo`). Essa URL e
  **permanente** — substituiu a presigned do MinIO, que expirava em 7 dias e
  derrubava todas as fotos ja publicadas.

## Checklist de ativacao (quando contratar a VPS)

> Antes de executar: leia o [DEPLOY.md](DEPLOY.md). Ele cobre as armadilhas que
> travam a subida — bloqueio do Let's Encrypt por tentativa falha, se trancar
> fora do SSH, DNS, e como sair de cada uma.

1. **VPS**: qualquer Linux com **8 GB** de RAM (sao 5 JVMs + Zeebe + Postgres +
   Redis + MinIO; o Zeebe sozinho quer ~1 GB). Instalar Docker:
   `curl -fsSL https://get.docker.com | sh`
2. **DNS**: apontar um A/AAAA do dominio da API (ex.: `api.seudominio.com`) para
   o IP da VPS **antes** do primeiro `up` — o Let's Encrypt valida por HTTP e
   falha se o dominio ainda nao resolver.
3. **Usuario de deploy**: criar usuario `deploy` com chave SSH propria e
   permissao no grupo `docker`.
4. **Pasta**: criar `~/trilha` no servidor.
5. **Configuracao local do servidor** (uma vez, na VPS):
   - copiar `.env.example` -> `~/trilha/.env` e preencher as senhas;
   - preencher `API_DOMAIN` e `ACME_EMAIL` (usados pelo Caddy no TLS);
   - apontar `JWT_ISSUER`, `EMAIL_CONFIRMACAO_URL` e `MIDIA_PUBLIC_URL` para o
     dominio real. **`EMAIL_CONFIRMACAO_URL` tem que ser a rota do BFF**
     (`/bff/usuarios/confirmar-email`): `/auth/confirmar-email` e do Cadastro,
     que nao e exposto — o link do e-mail daria 404 e ninguem ativaria a conta;
   - gerar a chave JWT: `mkdir -p ~/trilha/keys && openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out ~/trilha/keys/jwt-private.pem`
   - gerar credenciais do broker: `mosquitto_passwd -c ~/trilha/mosquitto/passwd loc-consumer`
     e copiar `mosquitto/acl.example` -> `~/trilha/mosquitto/acl` ajustando os usuarios;
   - preencher `MQTT_USERNAME`/`MQTT_PASSWORD` no `.env` com **as mesmas** credenciais
     do `passwd` acima — o broker de prod recusa conexao anonima;
   - preencher `CORS_ALLOWED_ORIGINS` com a origem publica do front no Firebase.
6. **Secrets no GitHub** (neste repo, Settings > Secrets and variables > Actions):
   `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`.
7. **Primeiro deploy**: aba Actions > Deploy > Run workflow (`todos`).
8. **Front web**: no repo `TrishaWeb`, preencher o dominio da API em `.env.prod`
   e rodar o workflow `Deploy web` (precisa dos secrets `FIREBASE_SERVICE_ACCOUNT`
   e `FIREBASE_PROJECT_ID`).

### Conferencia do primeiro boot

O `usuario` e criado pelo Cadastro e lido pelo APP no mesmo banco. As duas
migrations de schema base criam a tabela com a **mesma definicao** e
`IF NOT EXISTS`, entao a ordem de subida nao importa — mas vale conferir que os
dois subiram limpos antes de testar o cadastro:

```bash
docker compose -f docker-compose.prod.yml logs cadastro app | grep -i -E "flyway|started|error"
```

## Sobre as imagens

Cada repo de servico publica `ghcr.io/rafaeldossanto/trilha-<svc>` com as
tags `latest` e `sha-<commit>`. Para fixar uma versao no compose, troque a
tag `latest` pelo `sha-...` desejado (rollback = apontar para o sha anterior
e rodar o deploy de novo).

> Pacotes novos no ghcr.io nascem privados. Na primeira publicacao de cada
> imagem, va em Packages > (imagem) > Package settings e de acesso de
> leitura a VPS — ou deixe publico, ou gere um PAT `read:packages` para o
> `docker login ghcr.io` na VPS.
