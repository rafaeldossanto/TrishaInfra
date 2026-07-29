# Política de segurança — Trisha

O Trisha é um projeto open source, e todo o código dos serviços é público. Isso é
deliberado: a segurança do sistema não depende de esconder o código, e sim de
manter os **segredos** fora dele.

## Como reportar uma vulnerabilidade

**Não abra issue pública.** Uma issue com um exploit funcional expõe todos os
usuários até a correção subir.

Use um destes canais privados:

1. **GitHub Security Advisories** — na aba *Security* do repositório afetado,
   em *Report a vulnerability*. É o caminho preferido: fica registrado e permite
   discussão privada.
2. **E-mail** — rafael.santoss2802@gmail.com com o assunto `[SEGURANCA] Trisha`.

Ajuda muito incluir: o serviço afetado, os passos para reproduzir, o impacto que
você conseguiu demonstrar e, se possível, uma sugestão de correção.

Este é um projeto pessoal mantido por uma pessoa nas horas livres — não há SLA.
O compromisso é responder ao contato inicial em até uma semana e tratar como
prioridade qualquer coisa que exponha dado de usuário.

## Escopo

Interessa especialmente:

- Acesso a dado de outro usuário (aventura, ponto de interesse, mídia ou
  posição GPS de quem não te autorizou)
- Falha na validação do token (forja, escalonamento de privilégio)
- Bypass das regras de visibilidade (`PRIVADA`, `SO_GRUPO`, `AMIGOS`, `SEGUIDORES`)
- Injeção (SQL, comando), XSS armazenado via upload de mídia
- Qualquer forma de ler ou escrever no banco sem passar pela autorização

## O que **não** é vulnerabilidade

Para poupar seu tempo — estes pontos são conhecidos e intencionais:

- **`Cadastro/src/main/resources/keys/dev-private-key.pem`** — chave RSA
  versionada de propósito, exclusiva para desenvolvimento local. Ela **não
  assina token em produção**: o `JwtKeyConfig` aborta o boot se
  `JWT_RSA_PRIVATE_KEY_PATH` não estiver definida e nenhum profile de
  desenvolvimento (`dev`/`test`) estiver ativo. Ver `JwtKeyConfigTest`.
- **Credenciais em `compose.yaml` e `setup_trilha_db.sql`** (`myuser`/`secret`)
  — ambiente local apenas. Produção usa senhas geradas, fora do repositório.
- **`GET /arquivo/{id}/conteudo` é público** — é a URL que vai em `<img src>`, e
  tag de imagem não envia `Authorization`. A proteção é o id opaco (UUID v4),
  o mesmo modelo da presigned URL que este endpoint substituiu. Se você
  conseguir **enumerar** ids ou obter conteúdo sem conhecer o id, isso sim é
  vulnerabilidade.
- **`/amizade/sao-amigos` e `/seguidor/segue` respondem a qualquer usuário
  autenticado** — são consultados internamente pelo serviço de Localização.
  Aceito no MVP; se você achar como usar isso para mapear o grafo social de
  terceiros em escala, reporte.
- **`/auth/aceitar-termos` e `/auth/reenviar-email` são públicos e identificados
  por UUID** — conta `PENDENTE` ainda não tem token. Limitação conhecida.

## Como os segredos são tratados

Nenhum segredo de produção existe no repositório. Todos vêm de variáveis de
ambiente definidas no `.env` da máquina de produção, que está no `.gitignore`
junto com `keys/`, `mosquitto/passwd` e `mosquitto/acl`.

| Segredo | Origem |
|---|---|
| Senha do Postgres | `.env` (gerada com `openssl rand`) |
| Credenciais do MinIO | `.env` |
| Usuário/senha do MQTT | `.env` + `mosquitto/passwd` |
| Chave RSA de assinatura do JWT | arquivo PEM montado por volume, gerado na máquina |
| Credenciais SMTP | `.env` |

A chave RSA de produção nunca sai da máquina. Perdê-la invalida todos os tokens
em circulação (o `kid` é derivado dela), então ela deve ter cópia em um
gerenciador de senhas.

## Arquitetura de autorização

Contexto útil para quem for auditar:

- O serviço **Cadastro** assina os JWT (RSA) e publica a chave pública em
  `/oauth2/jwks`. Os outros quatro serviços são resource servers e validam por
  ali — não existe segredo compartilhado entre serviços.
- **Cada serviço reforça a visibilidade por conta própria.** O BFF não é a única
  porta: `loc` e `midia` são resource servers alcançáveis com qualquer token
  válido. Confiar apenas no filtro do BFF vazaria dados numa chamada direta —
  por isso a checagem é repetida em cada serviço.
- Em produção nada é publicado no host além do reverse proxy (80/443) e do
  broker MQTT (1883). Os serviços conversam por rede Docker interna.
- O BFF aplica rate limit por IP (janela fixa no Redis) e o Cadastro aplica
  lockout de conta após falhas de login consecutivas.
