-- Roda apenas no PRIMEIRO boot do container Postgres (volume vazio).
-- O usuario ja e criado pelo proprio entrypoint via POSTGRES_USER/POSTGRES_PASSWORD;
-- aqui so criamos os bancos de cada servico.

CREATE DATABASE trilha_cadastro;
CREATE DATABASE trilha_app;
CREATE DATABASE trilha_localizacao;
CREATE DATABASE trilha_midia;
