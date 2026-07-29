# Guia de subida — o que pode dar errado e como sair

Companheiro do checklist do [README](README.md). Aqui estão as armadilhas que
travam o deploy, cada uma com **como evitar** e **como sair**.

Leia a seção 1 **antes** de tocar no servidor. Ela é a diferença entre um susto
de dois minutos e um sábado perdido.

---

## 1. A saída de emergência: leia isto primeiro

**A Hostinger tem um console pelo navegador** (procure por *Browser terminal*,
*Console* ou *VNC* no painel da VPS). Ele **não usa SSH**: entra direto na
máquina como se você estivesse na frente dela, com teclado e monitor.

Isso importa porque quase todo desastre de deploy é a mesma coisa: **você se
tranca fora do servidor pelo SSH**. O console web continua funcionando quando o
SSH não funciona mais. Localize esse botão no painel **antes** de precisar dele.

**A regra de ouro do SSH:** enquanto estiver mexendo em qualquer coisa
relacionada a acesso (chaves, `sshd_config`, firewall, fail2ban), **mantenha a
sessão que funciona aberta** e teste a mudança em uma **segunda janela**. Se a
segunda janela falhar, você ainda tem a primeira para desfazer. Fechar a sessão
boa antes de confirmar que a nova funciona é o erro clássico.

---

## 2. Ban do Let's Encrypt (o cenário que você descreveu)

É real e acontece com quem erra o preenchimento. O Let's Encrypt limita
**tentativas falhas de validação** — na ordem de **5 por hora** para o mesmo
hostname — e também o total de certificados por domínio por semana (~50).

O Caddy tenta emitir o certificado assim que sobe. Se algo estiver errado, ele
**tenta de novo em loop** e queima suas tentativas sozinho, sem você fazer nada.

### O que causa a falha

| Causa | Sintoma no log do Caddy |
|---|---|
| DNS ainda não aponta para a VPS | `no such host` / timeout na validação |
| Porta 80 fechada no firewall | `connection refused` durante o challenge |
| `API_DOMAIN` escrito errado no `.env` | tenta certificado para o domínio errado |
| Proxy da Cloudflare ligado (nuvem laranja) | a Cloudflare responde ao challenge, não o Caddy |

### Como evitar: teste no ambiente de staging

Esta é a precaução mais importante deste documento. O Let's Encrypt tem um
ambiente de **teste** com limites altíssimos. Você valida todo o fluxo lá e só
depois emite o certificado real.

Adicione temporariamente no bloco global do `Caddyfile`, na VPS:

```
{
	email {$ACME_EMAIL}
	acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
}
```

Suba a stack. O navegador vai reclamar que o certificado não é confiável — **isso
é esperado e correto**: significa que todo o caminho funcionou (DNS, porta 80,
Caddy, validação). Aí você remove a linha `acme_ca`, roda:

```bash
docker compose -f docker-compose.prod.yml restart caddy
```

e recebe o certificado de verdade, na primeira tentativa.

### Se você já tomou o bloqueio

Não há como acelerar: **espere uma hora**. Enquanto espera:

1. **Pare o Caddy**, para ele não continuar queimando tentativas:
   ```bash
   docker compose -f docker-compose.prod.yml stop caddy
   ```
2. Corrija a causa (DNS, porta, `.env`).
3. Confirme que está tudo certo antes de subir de novo.

Ver o log para saber o que aconteceu:

```bash
docker compose -f docker-compose.prod.yml logs --tail 50 caddy
```

---

## 3. Se trancar fora da VPS

As quatro causas, em ordem de frequência:

### 3.1. Desabilitar a senha do SSH antes de testar a chave

O erro: você edita `PasswordAuthentication no`, reinicia o SSH, fecha a janela —
e descobre que a chave não estava configurada certo.

**Ordem segura:**
1. Coloque a chave pública em `~/.ssh/authorized_keys`
2. **Em outra janela**, conecte com a chave e confirme que entra
3. **Só então** desabilite a senha
4. Teste mais uma vez, em uma terceira janela, antes de fechar tudo

### 3.2. Firewall bloqueando a porta 22

O clássico: `ufw enable` **sem antes** ter liberado o SSH. O firewall sobe
bloqueando tudo, inclusive a sua conexão atual.

**Ordem correta — o allow vem antes do enable:**

```bash
ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp && ufw allow 1883/tcp
```

E só depois:

```bash
ufw enable
```

Se a Hostinger já tem firewall no painel, prefira usar o do painel — mudança
errada lá você desfaz pelo navegador, sem depender de acesso à máquina.

### 3.3. O fail2ban banindo você mesmo

O fail2ban bane IP que erra o login repetidamente — **inclusive o seu**, se você
errar a chave algumas vezes. O ban padrão é de cerca de 10 minutos.

Se acontecer: espere 10 minutos, ou entre pelo console web e libere:

```bash
fail2ban-client set sshd unbanip SEU.IP.AQUI
```

Para evitar de vez, adicione seu IP à lista de ignorados do fail2ban — mas
lembre que IP residencial muda.

### 3.4. Erro de sintaxe no sshd_config

Depois de editar, **valide antes de reiniciar**:

```bash
sshd -t
```

Sem saída = configuração válida. Se reclamar, corrija antes do restart.

---

## 4. DNS

Não existe ban, mas existe espera — e errar significa esperar de novo.

**Não confunda os dois níveis:**

- **Nameserver (NS)**: define **quem responde** pelo seu domínio. É o que você
  troca no Registro.br para apontar para a Cloudflare. Propagação: horas.
- **Registro A**: define **para qual IP** um nome aponta. É o que você cria no
  painel da Cloudflare. Propagação: minutos.

Só troque o NS **uma vez**. Cada troca reinicia a espera.

**Confirme antes de subir a stack:**

```bash
nslookup api.trisha.com.br
```

Precisa devolver o IP da sua VPS. Se devolver outra coisa, ou "não encontrado",
**não suba o Caddy ainda** — você só vai queimar tentativas do Let's Encrypt.

**Deixe a nuvem CINZA** (DNS only) no registro `api` da Cloudflare. Laranja
(proxy) quebra a validação do certificado.

---

## 5. E-mail de confirmação

Aqui tem um risco que não é técnico: **bloqueio da sua conta pessoal**.

Se você usar o Gmail como SMTP:

- Precisa de uma **senha de app** (exige 2FA na conta), não a sua senha normal
- Limite em torno de **500 envios/dia**
- O Google pode **bloquear a conta** por atividade suspeita se um servidor
  desconhecido começar a enviar em volume

Para produção, prefira um serviço transacional — **Brevo** e **Resend** têm
plano gratuito suficiente para começar, e você configura SPF/DKIM no DNS, o que
melhora muito a entrega (e-mail de confirmação que cai no spam é usuário perdido).

**Para testar sem enviar nada de verdade**, use o **Mailtrap**: ele captura os
e-mails numa caixa falsa. É o jeito de validar o fluxo de cadastro sem risco.

Teste o cadastro ponta a ponta antes de divulgar o app: se o e-mail não chega,
**ninguém consegue ativar a conta** e o app fica inutilizável.

---

## 6. Imagens Docker

**As imagens do ghcr.io nascem privadas.** No primeiro deploy o pull falha com
`unauthorized` ou `denied`.

Duas saídas:
- Tornar cada pacote público: GitHub > seu perfil > Packages > (imagem) >
  *Package settings* > *Change visibility*
- Ou fazer login na VPS com um token de acesso pessoal com escopo `read:packages`:
  ```bash
  docker login ghcr.io
  ```

Faça isso **antes** do deploy — são 5 pacotes (`trilha-app`, `trilha-cadastro`,
`trilha-bff`, `trilha-loc`, `trilha-midia`).

---

## 7. Antes de subir — checklist

- [ ] Localizei o **console web** da Hostinger no painel
- [ ] Chave SSH testada em segunda janela **antes** de desabilitar a senha
- [ ] Portas liberadas: 22, 80, 443, 1883 (allow antes do enable)
- [ ] `nslookup api.trisha.com.br` devolve o IP da VPS
- [ ] Registro `api` na Cloudflare está **DNS only** (cinza)
- [ ] `.env` preenchido, com senhas geradas por `openssl rand -base64 32`
- [ ] Chave JWT gerada na VPS **e copiada para o gerenciador de senhas**
- [ ] Imagens do ghcr.io públicas ou `docker login` feito
- [ ] `acme_ca` de staging no Caddyfile para o primeiro teste
- [ ] **Snapshot da VPS** feito depois da configuração base e antes do deploy

O snapshot é o seguro mais barato que existe: se algo der muito errado, você
volta ao estado bom em minutos em vez de refazer tudo.

### Guarde no gerenciador de senhas

Perder qualquer um destes dói:

| Item | O que acontece se perder |
|---|---|
| Chave SSH privada | Só entra pelo console web |
| `.env` (senhas) | Precisa recriar tudo e migrar o banco |
| **Chave JWT (`keys/jwt-private.pem`)** | **Todos os usuários são deslogados** e tokens em circulação param de valer |
| Acesso Cloudflare / Registro.br | Perde o controle do domínio |

### Ordem de subida (2 vCPUs pedem calma)

```bash
docker compose -f docker-compose.prod.yml up -d postgres redis minio zeebe mosquitto
```

Espere estabilizar e confira:

```bash
docker compose -f docker-compose.prod.yml ps
```

Depois os serviços e por último o proxy:

```bash
docker compose -f docker-compose.prod.yml up -d
```

Com 2 vCPUs, cinco JVMs subindo juntas levam alguns minutos. Lentidão no
primeiro boot é esperada.

---

## 8. Depois de subir — checklist

- [ ] `https://api.trisha.com.br/actuator/health` responde **404** (o Caddy
      bloqueia o actuator de propósito — 404 aqui é sinal de que a regra funciona)
- [ ] Cadastro ponta a ponta: criar conta → **e-mail chega** → confirmar → logar
- [ ] Upload de foto funciona e a imagem **aparece** no app
- [ ] Rastreio grava ponto e o "ao vivo" conecta (é o WebSocket passando pelo proxy)
- [ ] **Auto-renovação do domínio ligada** no Registro.br
- [ ] Backup do Postgres agendado
- [ ] 2FA ativo: GitHub, Cloudflare, Registro.br, Hostinger, Google

### Backup do banco

Não existe hoje, e é a maior lacuna que sobra depois do deploy. Se a VPS morrer,
o banco vai com ela. Um `pg_dump` diário resolve:

```bash
docker compose -f docker-compose.prod.yml exec -T postgres pg_dumpall -U "$DB_USERNAME" | gzip > ~/backup-$(date +%F).sql.gz
```

Coloque no cron (`crontab -e`) e, idealmente, mande o arquivo para fora da
máquina — backup que vive só no servidor não protege contra o servidor morrer.

### Renovação do domínio

Domínio expirado derruba **tudo** — site, API e e-mail — e o certificado também
para de renovar. Ligue a renovação automática e confirme que o cartão cadastrado
não vai vencer antes.

---

## 9. Sobrevivência no terminal

Comandos que resolvem 90% das dúvidas durante um deploy.

### Ver o que está rodando

```bash
docker compose -f docker-compose.prod.yml ps
```

A coluna `STATUS` é o que importa. `Restarting` em loop = o serviço está
quebrando ao subir; vá direto ao log dele.

### Ver logs

```bash
docker compose -f docker-compose.prod.yml logs --tail 50 cadastro
```

Trocando `cadastro` pelo serviço que interessa. Para acompanhar ao vivo, adicione
`-f` — e saia com **Ctrl+C** (isso interrompe só o log, não o serviço).

### Reiniciar um serviço

```bash
docker compose -f docker-compose.prod.yml restart bff
```

### Espaço em disco

```bash
df -h /
```

Se a partição `/` passar de 80%, é hora de agir — o MinIO guarda todas as fotos
ali. Para limpar imagens Docker antigas:

```bash
docker image prune -a -f
```

### Memória

```bash
free -h
```

### Sair de um editor de texto

O que mais trava quem tem pouca prática. Prefira o `nano`:

```bash
nano arquivo.txt
```

- Salvar: **Ctrl+O**, depois **Enter**
- Sair: **Ctrl+X**

Se cair no `vi`/`vim` sem querer: aperte **Esc**, digite `:q!` e **Enter** para
sair sem salvar.

### Editar o .env com segurança

Antes de editar, faça uma cópia:

```bash
cp .env .env.bak
```

Se estragar, `cp .env.bak .env` volta atrás.

---

## 10. Onde procurar quando algo não funciona

| Sintoma | Onde olhar |
|---|---|
| Navegador não abre a API | log do `caddy` — provavelmente certificado ou DNS |
| Erro de certificado | log do `caddy`; confira DNS e se a nuvem está cinza |
| API responde 502 | o serviço por trás não subiu; `ps` e log dele |
| Cadastro falha | log do `cadastro`; sem Zeebe saudável ele falha por design |
| GPS não grava | log do `loc`; e se o Postgres tem PostGIS |
| Foto não aparece | log do `midia`; e se `MIDIA_PUBLIC_URL` tem o domínio certo |
| Nada funciona depois de mexer no `.env` | erro de digitação; `cp .env.bak .env` |

Regra geral: **o log do serviço que falhou diz o que aconteceu.** Antes de mudar
qualquer configuração, leia o log — mudar às cegas costuma criar um segundo
problema em cima do primeiro.
