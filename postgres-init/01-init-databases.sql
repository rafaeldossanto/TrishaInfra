-- Roda apenas no PRIMEIRO boot do container Postgres (volume vazio).
-- O usuario ja e criado pelo proprio entrypoint via POSTGRES_USER/POSTGRES_PASSWORD;
-- aqui so criamos os bancos de cada servico.
--
-- 'trisha' e COMPARTILHADO entre Cadastro e APP: a entidade User do APP e uma
-- view read-only (@Immutable) da tabela 'usuario' que o Cadastro escreve. Com
-- bancos separados essa copia nasce vazia e toda a camada social (busca de
-- usuario, seguir por codigo, nome do autor no feed) para de funcionar.
-- Cada servico tem historico proprio do Flyway no mesmo schema (o APP usa
-- spring.flyway.table=flyway_schema_history_app), senao as sequencias de
-- versao dos dois colidiriam.

CREATE DATABASE trisha;
CREATE DATABASE trilha_localizacao;
CREATE DATABASE trilha_midia;
