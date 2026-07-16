# trilha-infra

Infraestrutura de producao do Trilha: compose com os 5 microservicos
(imagens do ghcr.io) + Postgres, Redis, MinIO e Mosquitto, e o workflow de
deploy via SSH.

**Estado atual: DORMENTE.** Nenhuma VPS contratada; o pipeline de cada
servico ja publica imagens no ghcr.io a cada merge na master, e este repo
deixa o deploy pronto para quando existir servidor.

## Arquitetura do deploy

```
push na master (cada repo) ──> CI: testes ──> imagem ghcr.io/rafaeldossanto/trilha-<svc>:latest
                                                        │
deploy.yml (clique manual) ──> SSH na VPS ──> docker compose pull + up -d ◄┘
```

- So o **BFF (8090)** e o **Mosquitto (1883)** ficam expostos; os demais
  servicos so conversam pela rede interna do compose.
- Postgres cria os 4 bancos (`trilha_cadastro`, `trilha_app`,
  `trilha_localizacao`, `trilha_midia`) no primeiro boot.
- O Cadastro **aborta o boot** em prod sem a chave RSA montada em
  `./keys/jwt-private.pem` (comportamento intencional).

## Checklist de ativacao (quando contratar a VPS)

1. **VPS**: qualquer Linux com 4 GB+ de RAM. Instalar Docker:
   `curl -fsSL https://get.docker.com | sh`
2. **Usuario de deploy**: criar usuario `deploy` com chave SSH propria e
   permissao no grupo `docker`.
3. **Pasta**: criar `~/trilha` no servidor.
4. **Configuracao local do servidor** (uma vez, na VPS):
   - copiar `.env.example` -> `~/trilha/.env` e preencher as senhas;
   - gerar a chave JWT: `mkdir -p ~/trilha/keys && openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out ~/trilha/keys/jwt-private.pem`
   - gerar credenciais do broker: `mosquitto_passwd -c ~/trilha/mosquitto/passwd loc-consumer`
     e copiar `mosquitto/acl.example` -> `~/trilha/mosquitto/acl` ajustando os usuarios;
   - definir `MQTT_CLIENT_ID`/usuario e senha do loc no `.env` se o broker exigir auth
     (hoje o loc conecta anonimo — ajustar quando ativar).
5. **Secrets no GitHub** (neste repo, Settings > Secrets and variables > Actions):
   `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`.
6. **Primeiro deploy**: aba Actions > Deploy > Run workflow (`todos`).
7. **Depois**: colocar um reverse proxy com TLS (Caddy e o mais simples)
   na frente do BFF e trocar `JWT_ISSUER`/`EMAIL_CONFIRMACAO_URL` no `.env`
   para o dominio real.

## Sobre as imagens

Cada repo de servico publica `ghcr.io/rafaeldossanto/trilha-<svc>` com as
tags `latest` e `sha-<commit>`. Para fixar uma versao no compose, troque a
tag `latest` pelo `sha-...` desejado (rollback = apontar para o sha anterior
e rodar o deploy de novo).

> Pacotes novos no ghcr.io nascem privados. Na primeira publicacao de cada
> imagem, va em Packages > (imagem) > Package settings e de acesso de
> leitura a VPS — ou deixe publico, ou gere um PAT `read:packages` para o
> `docker login ghcr.io` na VPS.
