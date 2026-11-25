# NovaPay — Roteiro de testes e evidências

**Equipe:** Nathan Junio (Arquiteto DDL) · Kauã Martins (Executor MySQL) · Bruno Avelino (Auditor / Testador)

Cada teste abaixo foi validado num MySQL 8.0. A coluna **Resultado esperado** mostra a saída real obtida. Tire um print de cada um e cole no lugar indicado.

> **Dica:** use o terminal (`mysql -u USUARIO -p -h 127.0.0.1`) para os testes de login. O MySQL Workbench abre mais de uma conexão por aba, então pode bagunçar o teste de limite da bi_ana.

---

## Etapa 0 — Setup (Executor)

| # | Comando (como root) | Resultado esperado |
|---|---|---|
| 0.1 | `mysql -u root -p < script_seguranca_novapay.sql` | Roda sem erros |
| 0.2 | `SELECT * FROM novapay_db.clientes;` | 2 clientes (Mariana Costa e Carlos Eduardo) |

📸 *Print 0: tabelas criadas e populadas*

---

## Etapa 1 — Contas e ciclo de vida (Auditor)

**1.1 Conta bloqueada.** Rode só a Etapa 1 até o `CREATE USER 'auditor_ext'` (antes do `ACCOUNT UNLOCK`). Em outro terminal:

```
mysql -u auditor_ext -p -h 127.0.0.1      (senha: Audit@2026!)
```

Resultado esperado:
```
ERROR 3118 (HY000): Access denied for user 'auditor_ext'@'localhost'. Account is locked.
```
📸 *Print 1.1: erro 3118*

**1.2 Desbloqueio.** O Executor roda `ALTER USER 'auditor_ext'@'%' ACCOUNT UNLOCK;` e o Auditor tenta de novo → login funciona.

📸 *Print 1.2: login do auditor_ext funcionando*

**1.3 Senha expirada (dev_lucas).** Ele só conecta a partir de `192.168.10.x`. De `localhost`, o esperado é:
```
ERROR 1045 (28000): Access denied for user 'dev_lucas'@'localhost' (using password: YES)
```
Isso já prova a restrição de host. Para provar o `PASSWORD EXPIRE`, mostre a consulta abaixo (como root):
```sql
SELECT user, host, password_expired FROM mysql.user WHERE user = 'dev_lucas';
-- dev_lucas | 192.168.10.% | Y
```
Se alguém estiver na sub-rede 192.168.10.x, ao logar e rodar qualquer comando aparece:
```
ERROR 1820 (HY000): You must reset your password using ALTER USER statement before executing this statement.
```
📸 *Print 1.3: erro 1045 + password_expired = Y*

---

## Etapa 2 — Menor privilégio (Auditor)

**estagiario_suporte** (senha `Sup@2026!`) — teste obrigatório de LGPD

| # | Comando | Resultado esperado |
|---|---|---|
| 2.1 | `SELECT * FROM novapay_db.clientes;` | ❌ `ERROR 1142 (42000): SELECT command denied to user 'estagiario_suporte'@'localhost' for table 'clientes'` |
| 2.2 | `SELECT id_cliente, nome, telefone FROM novapay_db.clientes;` | ✅ Lista os 2 clientes |
| 2.3 | `SELECT cpf FROM novapay_db.clientes;` | ❌ `ERROR 1143 (42000): ... for column 'cpf' in table 'clientes'` |
| 2.4 | `UPDATE novapay_db.clientes SET telefone='(11) 90000-0000' WHERE id_cliente=2;` | ✅ Atualiza |
| 2.5 | `UPDATE novapay_db.clientes SET saldo=999999 WHERE id_cliente=2;` | ❌ `ERROR 1143 (42000): UPDATE command denied ... for column 'saldo'` |

📸 *Print 2.A: testes do estagiario_suporte*

**app_backend** (senha `App@Nova2026!`)

| # | Comando | Resultado esperado |
|---|---|---|
| 2.6 | `INSERT INTO novapay_db.logs_auditoria (evento) VALUES ('teste app');` | ✅ Insere |
| 2.7 | `UPDATE novapay_db.logs_auditoria SET evento='x';` | ❌ `ERROR 1142: UPDATE command denied ... for table 'logs_auditoria'` |
| 2.8 | `DELETE FROM novapay_db.logs_auditoria;` | ❌ `ERROR 1142: DELETE command denied ... for table 'logs_auditoria'` |
| 2.9 | `DELETE FROM novapay_db.transacoes WHERE id_transacao=1;` | ❌ `ERROR 1142: DELETE command denied ... for table 'transacoes'` (prova o REVOKE) |
| 2.10 | `DROP TABLE novapay_db.clientes;` | ❌ `ERROR 1142: DROP command denied ...` |

📸 *Print 2.B: testes do app_backend*

**auditor_ext** (senha `Audit@2026!`)

| # | Comando | Resultado esperado |
|---|---|---|
| 2.11 | `SELECT nome, cpf, saldo FROM novapay_db.clientes;` | ✅ Lê tudo |
| 2.12 | `DELETE FROM novapay_db.logs_auditoria;` | ❌ `ERROR 1142: DELETE command denied ...` |
| 2.13 | `GRANT SELECT ON novapay_db.clientes TO 'bi_bruno'@'%';` | ❌ `ERROR 1142: GRANT command denied ...` (sem GRANT OPTION) |

📸 *Print 2.C: testes do auditor_ext*

---

## Etapa 3 — Roles e limites (Auditor)

**bi_ana / bi_bruno** (senha `Bi@Nova2026!`)

| # | Comando | Resultado esperado |
|---|---|---|
| 3.1 | `SELECT CURRENT_ROLE();` | `` `role_analista_bi`@`%` `` (role ativa no login) |
| 3.2 | `SELECT * FROM novapay_db.transacoes;` | ✅ Lista a transação PIX |
| 3.3 | `SELECT id_cliente, nome FROM novapay_db.clientes;` | ✅ Lista os 2 clientes |
| 3.4 | `SELECT cpf FROM novapay_db.clientes;` | ❌ `ERROR 1143: ... for column 'cpf'` |

📸 *Print 3.A: role ativa e permissões da bi_ana/bi_bruno*

**3.5 Teste de estresse.** Abra 3 terminais e conecte com `mysql -u bi_ana -p -h 127.0.0.1` em cada um, sem fechar os anteriores. Os 2 primeiros conectam; o 3º recebe:
```
ERROR 1226 (42000): User 'bi_ana' has exceeded the 'max_user_connections' resource (current value: 2)
```
📸 *Print 3.B: erro 1226 na 3ª conexão*

---

## Etapa 4 — Auditoria final (Executor, como root)

```sql
SHOW GRANTS FOR 'estagiario_suporte'@'localhost';
SHOW GRANTS FOR 'bi_ana'@'%' USING 'role_analista_bi';
```
Resultado esperado:
```
GRANT USAGE ON *.* TO `estagiario_suporte`@`localhost`
GRANT SELECT (`id_cliente`, `nome`, `telefone`), UPDATE (`telefone`) ON `novapay_db`.`clientes` TO `estagiario_suporte`@`localhost`

GRANT USAGE ON *.* TO `bi_ana`@`%`
GRANT SELECT (`id_cliente`, `nome`) ON `novapay_db`.`clientes` TO `bi_ana`@`%`
GRANT SELECT ON `novapay_db`.`transacoes` TO `bi_ana`@`%`
GRANT `role_analista_bi`@`%` TO `bi_ana`@`%`
```
📸 *Print 4: saídas do SHOW GRANTS*

### Quiz da equipe
1. **Porque comandos DDL nativos já sincronizam a memória RAM e o disco automaticamente.**
2. **Ela recebe erro de Access Denied, pois a Role inicia desativada na sessão.** (Testamos: `CURRENT_ROLE()` volta `NONE` e o SELECT dá `ERROR 1142`.)

---

## Checklist de entrega
- [ ] `script_seguranca_novapay.sql`
- [ ] Prints 0, 1.1, 1.2, 1.3, 2.A, 2.B, 2.C, 3.A, 3.B, 4
