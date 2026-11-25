-- =====================================================================
--  NovaPay S.A. — Hardening de Segurança do MySQL 8.0+
--  Arquivo: script_seguranca_novapay.sql
--  Disciplina: Gerenciamento de Banco de Dados — Laboratório Prático em Grupo
--
--  EQUIPE
--  Papel 1 (Arquiteto DDL) ........ Nathan Junio
--      Responsável por estruturar o script SQL limpo e comentado.
--  Papel 2 (Executor MySQL) ....... Kauã Martins
--      Roda os comandos no ambiente MySQL e valida as saídas.
--  Papel 3 (Auditor / Testador) ... Bruno Avelino
--      Realiza logins com os usuários criados para comprovar bloqueios
--      e permissões.
--
--  COMO EXECUTAR: conectar como root e rodar o arquivo inteiro.
--      mysql -u root -p < script_seguranca_novapay.sql
--  O script pode ser executado mais de uma vez (ele limpa usuários e
--  role antes de recriar).
-- =====================================================================


-- =====================================================================
--  ETAPA 0 — CENÁRIO & SETUP: banco novapay_db e tabelas iniciais
-- =====================================================================

DROP DATABASE IF EXISTS novapay_db;
CREATE DATABASE novapay_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE novapay_db;

CREATE TABLE clientes (
    id_cliente INT AUTO_INCREMENT PRIMARY KEY,
    nome       VARCHAR(100) NOT NULL,
    cpf        VARCHAR(14)  NOT NULL UNIQUE,
    telefone   VARCHAR(20),
    saldo      DECIMAL(12,2) DEFAULT 0.00
);

CREATE TABLE transacoes (
    id_transacao INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente   INT NOT NULL,
    valor        DECIMAL(12,2) NOT NULL,
    tipo         ENUM('PIX', 'TED', 'BOLETO') NOT NULL,
    data_hora    DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
);

CREATE TABLE logs_auditoria (
    id_log        INT AUTO_INCREMENT PRIMARY KEY,
    evento        VARCHAR(255) NOT NULL,
    registrado_em DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO clientes (nome, cpf, telefone, saldo) VALUES
    ('Mariana Costa',  '111.222.333-44', '(11) 98888-1111', 15400.50),
    ('Carlos Eduardo', '555.666.777-88', '(19) 97777-2222',   320.00);

INSERT INTO transacoes (id_cliente, valor, tipo) VALUES (1, 500.00, 'PIX');
INSERT INTO logs_auditoria (evento) VALUES ('Inicialização do sistema NovaPay');


-- ---------------------------------------------------------------------
--  Limpeza para reexecução: remove contas e role caso já existam.
-- ---------------------------------------------------------------------
DROP USER IF EXISTS
    'app_backend'@'localhost',
    'dev_lucas'@'192.168.10.%',
    'auditor_ext'@'%',
    'estagiario_suporte'@'localhost',
    'bi_ana'@'%',
    'bi_bruno'@'%';
DROP ROLE IF EXISTS 'role_analista_bi';


-- =====================================================================
--  ETAPA 1 — ANATOMIA & DDL: criação de contas e ciclo de vida
--  Uma conta no MySQL é o par 'usuario'@'host'. O host restringe DE
--  ONDE a conexão pode vir.
-- =====================================================================

-- Aplicação backend: roda na mesma máquina do banco.
-- Host 'localhost' => nenhuma conexão externa é aceita.
CREATE USER 'app_backend'@'localhost'
    IDENTIFIED BY 'App@Nova2026!';

-- Desenvolvedor: só pode conectar a partir da sub-rede da engenharia
-- (192.168.10.0/24). PASSWORD EXPIRE obriga a troca de senha no
-- próximo login (até trocar, nenhum outro comando é aceito).
CREATE USER 'dev_lucas'@'192.168.10.%'
    IDENTIFIED BY 'DevTemp#123'
    PASSWORD EXPIRE;

-- Auditor externo: pode vir de qualquer host ('%'), mas a conta nasce
-- BLOQUEADA até o início da auditoria.
CREATE USER 'auditor_ext'@'%'
    IDENTIFIED BY 'Audit@2026!'
    ACCOUNT LOCK;

-- Suporte interno nível 1: apenas local.
CREATE USER 'estagiario_suporte'@'localhost'
    IDENTIFIED BY 'Sup@2026!';

-- ---------------------------------------------------------------------
--  DESAFIO DE VALIDAÇÃO (feito pelo Auditor em outro terminal ANTES
--  da linha de desbloqueio abaixo):
--      mysql -u auditor_ext -p -h 127.0.0.1
--  Resultado obtido:
--      ERROR 3118 (HY000): Access denied for user 'auditor_ext'@'localhost'.
--      Account is locked.
--  Após registrar o erro, a auditoria começa e a conta é desbloqueada:
-- ---------------------------------------------------------------------
ALTER USER 'auditor_ext'@'%' ACCOUNT UNLOCK;


-- =====================================================================
--  ETAPA 2 — MATRIZ DE ESCOPOS: menor privilégio (GRANT & REVOKE)
--  Regra da equipe: nada de ALL PRIVILEGES e nada de *.*
-- =====================================================================

-- ---------------------------------------------------------------------
--  2.1 Aplicação Backend — 'app_backend'@'localhost'
--  clientes e transacoes: ler, inserir e atualizar.
--  logs_auditoria: apenas inserir e ler (logs imutáveis: sem UPDATE
--  e sem DELETE). Nenhum privilégio estrutural (DROP/ALTER/CREATE).
-- ---------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON novapay_db.clientes       TO 'app_backend'@'localhost';
GRANT SELECT, INSERT, UPDATE ON novapay_db.transacoes     TO 'app_backend'@'localhost';
GRANT SELECT, INSERT         ON novapay_db.logs_auditoria TO 'app_backend'@'localhost';

-- ---------------------------------------------------------------------
--  2.2 Suporte Nível 1 — 'estagiario_suporte'@'localhost'
--  Segurança em nível de COLUNA (LGPD): pode ler só id_cliente, nome
--  e telefone (cpf e saldo ficam invisíveis) e atualizar só telefone.
-- ---------------------------------------------------------------------
GRANT SELECT (id_cliente, nome, telefone),
      UPDATE (telefone)
   ON novapay_db.clientes
   TO 'estagiario_suporte'@'localhost';

-- ---------------------------------------------------------------------
--  2.3 Auditor Externo — 'auditor_ext'@'%'
--  Somente leitura em todo o banco novapay_db, SEM WITH GRANT OPTION
--  (não pode repassar privilégios para ninguém).
-- ---------------------------------------------------------------------
GRANT SELECT ON novapay_db.* TO 'auditor_ext'@'%';

-- ---------------------------------------------------------------------
--  2.4 Simulação de incidente
--  Um desenvolvedor concedeu DELETE em transacoes por engano...
-- ---------------------------------------------------------------------
GRANT DELETE ON novapay_db.transacoes TO 'app_backend'@'localhost';
-- ...correção cirúrgica: remove SOMENTE o DELETE dessa tabela.
-- SELECT, INSERT e UPDATE continuam intactos.
REVOKE DELETE ON novapay_db.transacoes FROM 'app_backend'@'localhost';


-- =====================================================================
--  ETAPA 3 — ROLES & LIMITES: governança e contenção de recursos
-- =====================================================================

-- ---------------------------------------------------------------------
--  3.1 Role padrão para os analistas de BI
--  transacoes: leitura completa.
--  clientes: leitura apenas de id_cliente e nome (sem cpf, telefone,
--  saldo).
-- ---------------------------------------------------------------------
CREATE ROLE 'role_analista_bi';

GRANT SELECT                     ON novapay_db.transacoes TO 'role_analista_bi';
GRANT SELECT (id_cliente, nome)  ON novapay_db.clientes   TO 'role_analista_bi';

-- ---------------------------------------------------------------------
--  3.2 Usuários de BI + atribuição da role
-- ---------------------------------------------------------------------
CREATE USER 'bi_ana'@'%'   IDENTIFIED BY 'Bi@Nova2026!';
CREATE USER 'bi_bruno'@'%' IDENTIFIED BY 'Bi@Nova2026!';

GRANT 'role_analista_bi' TO 'bi_ana'@'%', 'bi_bruno'@'%';

-- Sem esta linha a role fica DESATIVADA na sessão e o analista recebe
-- "SELECT command denied" mesmo tendo a role. Com DEFAULT ROLE ALL,
-- todas as roles concedidas são ativadas automaticamente no login.
SET DEFAULT ROLE ALL TO 'bi_ana'@'%', 'bi_bruno'@'%';

-- ---------------------------------------------------------------------
--  3.3 Proteção contra negação de serviço (Resource Limits)
--  bi_ana: no máximo 2 conexões simultâneas e 100 consultas por hora.
--  A 3ª conexão simultânea recebe:
--      ERROR 1226 (42000): User 'bi_ana' has exceeded the
--      'max_user_connections' resource (current value: 2)
-- ---------------------------------------------------------------------
ALTER USER 'bi_ana'@'%'
    WITH MAX_USER_CONNECTIONS 2
         MAX_QUERIES_PER_HOUR 100;


-- =====================================================================
--  ETAPA 4 — AUDITORIA FINAL
-- =====================================================================

-- Inspeção oficial dos privilégios aplicados
SHOW GRANTS FOR 'estagiario_suporte'@'localhost';
SHOW GRANTS FOR 'bi_ana'@'%' USING 'role_analista_bi';

-- Conferências extras da equipe
SHOW GRANTS FOR 'app_backend'@'localhost';   -- não deve aparecer DELETE
SHOW GRANTS FOR 'auditor_ext'@'%';           -- só SELECT, sem GRANT OPTION

SELECT user, host, account_locked, password_expired,
       max_user_connections, max_questions
  FROM mysql.user
 WHERE user IN ('app_backend', 'dev_lucas', 'auditor_ext',
                'estagiario_suporte', 'bi_ana', 'bi_bruno',
                'role_analista_bi')
 ORDER BY user;


-- =====================================================================
--  PERGUNTA TÉCNICA
--  "Por que NÃO colocamos o comando FLUSH PRIVILEGES; ao final deste
--   script?"
--
--  RESPOSTA:
--  Porque todos os comandos usados aqui (CREATE USER, ALTER USER,
--  GRANT, REVOKE, CREATE ROLE, SET DEFAULT ROLE, DROP USER/ROLE) são
--  comandos nativos de gerenciamento de contas. Ao executá-los, o
--  MySQL grava a mudança nas tabelas de privilégios (mysql.user,
--  mysql.tables_priv, mysql.columns_priv, mysql.role_edges, ...) E JÁ
--  ATUALIZA o cache de privilégios em memória na mesma hora. Ou seja,
--  disco e memória ficam sincronizados automaticamente.
--
--  O FLUSH PRIVILEGES só é necessário quando alguém altera as tabelas
--  de privilégios "na mão", com INSERT/UPDATE/DELETE direto em
--  mysql.user, por exemplo, porque aí o MySQL não fica sabendo da
--  mudança até recarregar as tabelas. Como não fizemos isso, o comando
--  seria redundante (e ainda exigiria o privilégio RELOAD sem
--  necessidade).
--
--  QUIZ DE VALIDAÇÃO DA EQUIPE
--  1) FLUSH PRIVILEGES é redundante após GRANT porque comandos DDL
--     nativos já sincronizam a memória RAM e o disco automaticamente.
--     (Ele NÃO foi removido do MySQL 8.0.)
--  2) Sem SET DEFAULT ROLE, a Ana recebe erro de acesso negado
--     (ERROR 1142 — SELECT command denied), pois a role começa
--     desativada na sessão. Ela teria que rodar SET ROLE manualmente.
-- =====================================================================
