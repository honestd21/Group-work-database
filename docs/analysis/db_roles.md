# Этап 2.4. Проект ролей PostgreSQL

Раздел переводит матрицу доступа (этап 2.2) и требования к защите (этап 2.3) в роли и привилегии PostgreSQL. Каждая ячейка матрицы здесь превращается в `GRANT` или в отсутствие `GRANT`. Готовые команды будут в `sql/roles.sql`. Рассчитано на PostgreSQL 16 и выше (управление членством в ролях в 16-й версии устроено иначе, чем в более ранних).

Объекты находятся в схеме `credit` (если в `schema.sql` используется другая схема, имя заменяется).

---

## 1. Перечень ролей

Права выдаются **групповым ролям** (`NOLOGIN`, войти под ними нельзя). Сотрудник получает личную учётную запись (`LOGIN`) и становится членом нужной группы. Увольнение или перевод сотрудника сводится к одной команде: исключению из группы.

| Роль | Тип | Вход | Назначение |
|---|---|---|---|
| `credit_manager` | групповая | нет | оформление клиентов, заявок и договоров |
| `underwriter` | групповая | нет | оценка заёмщика и решение по договору |
| `collector` | групповая | нет | работа с просроченными платежами |
| `data_analyst` | групповая | нет | отчёты и модели на обезличенных данных |
| `db_admin` | групповая | нет | структура БД, пользователи, справочник, мониторинг |
| `security_officer` | групповая | нет | чтение журнала аудита |
| `schema_owner` | служебная | нет | владелец схемы, таблиц, представлений и функций |
| `backup_service` | служебная | да | создание резервных копий |
| `job_service` | служебная | да | плановые задачи: удаление по сроку, приём платежей |

Всего 9 ролей (требование задания: не менее 3). Пример личных учётных записей: `manager_user` (в группе `credit_manager`), `analyst_user` (в `data_analyst`), `admin_user` (в `db_admin`).

---

## 2. Уровень базы данных и схемы

| Объект | Привилегии | Кому | Почему |
|---|---|---|---|
| База данных | `CONNECT` | шесть групповых ролей, служебные роли | у `PUBLIC` право `CONNECT` отзывается: подключиться может только тот, кому оно выдано |
| Схема `credit` | `USAGE` | шесть групповых ролей, служебные роли | без `USAGE` таблицы схемы недоступны, даже если права на них выданы |
| Схема `credit` | `CREATE` | никому, кроме владельца | пользователи не создают объекты в схеме |
| Схема `credit` | владелец | `schema_owner` | владелец отделён от администратора и от бизнес-ролей |
| Новые таблицы | права по умолчанию для `PUBLIC` отозваны | | новый объект не доступен никому, пока права не выданы явно |
| Функции | `EXECUTE` для `PUBLIC` отозвано | | в PostgreSQL по умолчанию каждая новая функция исполняется любым пользователем |

---

## 3. Привилегии на таблицы и представления

Обозначения: **S** `SELECT`, **I** `INSERT`, **U** `UPDATE`, **D** `DELETE`; «—» нет доступа. В скобках указаны столбцы, на которые право выдаётся только им.

| Объект | `credit_manager` | `underwriter` | `collector` | `data_analyst` | `db_admin` | `security_officer` |
|---|---|---|---|---|---|---|
| `ref_dictionary` | S | S | S | S | S, I, U, D | — |
| `client` | S, I, U | S | — | — | — | — |
| `v_client_anon` | — | — | — | S | — | — |
| `client_personal` | S, I, U | — | S (`client_id`, `last_name`, `first_name`, `middle_name`, `phone`) | — | — | — |
| `client_financials` | S, I, U | S | — | S | — | — |
| `application` | S, I, U (без скоринговых столбцов) | S | S (`application_id`, `client_id`) | S | — | — |
| `application_housing` | S, I, U | S | — | S | — | — |
| `loan_contract` | S, I | S, U (`status_ref_id`, `interest_rate`, `term_months`) | S (все, кроме `interest_rate`), U (`status_ref_id`) | S | — | — |
| `collateral` | S, I, U | S | — | S | — | — |
| `guarantor` | S, I, U | — | — | — | — | — |
| `previous_application` | — | S | — | S | — | — |
| `bureau` | — | S | — | S | — | — |
| `installments_payments` | — | S | — | S | — | — |
| `v_payments_current` | — | — | S | — | — | — |
| `audit_log` | — | — | — | — | — | S |

`DELETE` не выдан ни одной бизнес-роли (БП-5). Единственное исключение: администратор ведёт справочник `ref_dictionary`. `INSERT` в `installments_payments` и в `audit_log` не выдан никому: платежи вносит функция `fn_register_payment`, журнал пишут триггерные функции (БП-4).

Пояснения:
- **Скоринговые столбцы** `application`: `ext_source_1`, `ext_source_2`, `ext_source_3`, `bureau_enquiries_cnt`, `target`. `INSERT` менеджеру выдан на все столбцы, потому что `target` объявлен `NOT NULL` и значение нужно при создании строки. Изменить эти столбцы после вставки менеджер не может (БП-3).
- **Взыскание и `client_personal`.** В список столбцов включён `client_id`: без ключа невозможно найти нужную строку. Ключ не содержит ПДн.
- **Взыскание и `loan_contract`.** Запрос `SELECT *` у этой роли завершится ошибкой, потому что у неё нет права на `interest_rate`: столбцы нужно перечислять явно.
- **Идентификаторы.** Столбцы `GENERATED ALWAYS AS IDENTITY` при `INSERT` не требуют права на последовательность, поэтому отдельных прав на последовательности не выдаётся.

---

## 4. Функции и представления

| Объект | Тип | Владелец | Кто использует | Зачем |
|---|---|---|---|---|
| `v_client_anon` | представление | `schema_owner` | `data_analyst` (`SELECT`) | обезличенный `client` (этап 2.3) |
| `v_payments_current` | представление | `schema_owner` | `collector` (`SELECT`) | платежи только по текущим договорам (`contract_id IS NOT NULL`) |
| `fn_audit_log` | триггерная функция, `SECURITY DEFINER` | `schema_owner` | срабатывает от триггеров, прав на запуск не требует | запись в `audit_log` |
| `fn_register_payment` | функция, `SECURITY DEFINER` | `schema_owner` | `job_service` (`EXECUTE`) | единственный путь добавить платёж |
| `fn_purge_expired_data` | функция, `SECURITY DEFINER` | `schema_owner` | `job_service` (`EXECUTE`) | единственный путь удалить данные по сроку хранения |

Представления `v_client_anon` и `v_payments_current` создаются в `roles.sql`, функции в `triggers_functions.sql`.

Как это работает:
- **Представления** выполняются с правами владельца. Аналитик читает `v_client_anon`, не имея `SELECT` на `client`, а взыскание читает `v_payments_current`, не имея доступа к самой таблице платежей. Представления создаются с `security_barrier = true`, чтобы пользовательские функции в `WHERE` не могли увидеть скрытые строки.
- **`SECURITY DEFINER`** означает выполнение с правами владельца функции. Благодаря этому у `job_service` нет `INSERT` и `DELETE` на таблицы, но через функции он может выполнить только предусмотренные действия. У каждой такой функции фиксируется `SET search_path = credit, pg_temp`, иначе пользователь может подменить объекты в своём пути поиска.
- **Кто записан в журнале.** Внутри `SECURITY DEFINER`-функции `current_user` равен владельцу (`schema_owner`), а не сотруднику. Поэтому в `audit_log.db_user` функция `fn_audit_log` записывает `session_user`: это учётная запись, под которой человек вошёл в систему.

---

## 5. Служебные роли и особенности администратора

### 5.1. `schema_owner`

Владеет схемой, таблицами, представлениями и функциями. Войти под ней нельзя. Нужна, чтобы права на объекты были у технической роли, а не у человека и не у бизнес-роли. Именно её права использует `fn_purge_expired_data`, поэтому ни у кого из пользователей нет `DELETE`.

### 5.2. `db_admin`

Администратор управляет доступом, но не читает бизнес-данные и журнал аудита (БП-3).

| Что может | Как реализовано |
|---|---|
| Создавать учётные записи сотрудников | атрибут `CREATEROLE` у личной учётной записи администратора (атрибут не наследуется через группу, поэтому задаётся самой записи) |
| Включать сотрудников в группы и исключать | `ADMIN OPTION` на пять бизнес-ролей |
| Менять структуру | членство в `schema_owner` с `INHERIT FALSE, SET TRUE`: права владельца не действуют автоматически, а становятся доступны только после явной команды `SET ROLE schema_owner` |
| Вести справочник | `SELECT`, `INSERT`, `UPDATE`, `DELETE` на `ref_dictionary` |
| Мониторить сервер | членство в `pg_monitor`: представления `pg_stat_statements`, `pg_stat_user_tables`, размеры таблиц |

Чего у администратора нет: статуса суперпользователя, прав на бизнес-таблицы, права читать данные ролей-групп (в членстве `ADMIN OPTION` указано `INHERIT FALSE, SET FALSE`).

Остаточный риск: через `SET ROLE schema_owner` администратор может получить права владельца на таблицы. Он снижается журналированием: команды DDL и `GRANT` попадают в журнал сервера (`log_statement = 'ddl'`, расширение `pgaudit` с классами `role` и `ddl`), и журнал читает служба безопасности. `pg_stat_statements` хранит тексты запросов с константами, замещёнными параметрами (`$1`), поэтому значения ПДн в них не попадают.

### 5.3. `backup_service`

Вход разрешён. Атрибут `REPLICATION` для физических копий и членство в `pg_read_all_data` для логических (`pg_dump`). Эта роль технически читает все данные, включая ПДн, и является осознанным исключением из матрицы: резервная копия должна быть полной. Риск закрывается шифрованием копий, хранением ключей отдельно и подключением только с адреса сервера резервного копирования (правило в `pg_hba.conf`).

### 5.4. `job_service`

Вход разрешён. Только `EXECUTE` на `fn_register_payment` и `fn_purge_expired_data`. Прямых прав на таблицы нет.

### 5.5. Ограничения аналитика

Параметры роли не наследуются через группу, поэтому они задаются личным учётным записям аналитиков:

```sql
ALTER ROLE analyst_user SET statement_timeout = '10min';
ALTER ROLE analyst_user SET default_transaction_read_only = on;
```

Тяжёлый запрос прерывается через 10 минут и не блокирует базу, а сессия аналитика по умолчанию доступна только для чтения.

---

## 6. Эскиз `roles.sql`

```sql
-- 1. Роли
CREATE ROLE schema_owner      NOLOGIN;
CREATE ROLE credit_manager    NOLOGIN;
CREATE ROLE underwriter       NOLOGIN;
CREATE ROLE collector         NOLOGIN;
CREATE ROLE data_analyst      NOLOGIN;
CREATE ROLE db_admin          NOLOGIN;
CREATE ROLE security_officer  NOLOGIN;
CREATE ROLE backup_service    LOGIN REPLICATION PASSWORD :'backup_pwd';  -- пароль из переменной
CREATE ROLE job_service       LOGIN PASSWORD :'job_pwd';

-- 2. База и схема
REVOKE ALL ON DATABASE credit_db FROM PUBLIC;
GRANT CONNECT ON DATABASE credit_db
    TO credit_manager, underwriter, collector, data_analyst, db_admin,
       security_officer, backup_service, job_service;

ALTER SCHEMA credit OWNER TO schema_owner;
REVOKE ALL ON SCHEMA credit FROM PUBLIC;
GRANT USAGE ON SCHEMA credit
    TO credit_manager, underwriter, collector, data_analyst, db_admin,
       security_officer, backup_service, job_service;

ALTER DEFAULT PRIVILEGES FOR ROLE schema_owner IN SCHEMA credit
    REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE schema_owner
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- 3. Кредитный менеджер
GRANT SELECT ON ref_dictionary TO credit_manager;
GRANT SELECT, INSERT, UPDATE ON client, client_personal, client_financials,
      application_housing, collateral, guarantor TO credit_manager;
GRANT SELECT, INSERT ON application, loan_contract TO credit_manager;
GRANT UPDATE (client_id, contract_type_ref_id, application_date,
              amt_income_total, amt_credit, amt_annuity, amt_goods_price,
              cnt_fam_members, region_rating, region_population_relative)
      ON application TO credit_manager;

-- 4. Андеррайтер
GRANT SELECT ON ref_dictionary, client, client_financials, application,
      application_housing, loan_contract, collateral, previous_application,
      bureau, installments_payments TO underwriter;
GRANT UPDATE (status_ref_id, interest_rate, term_months)
      ON loan_contract TO underwriter;

-- 5. Служба взыскания
GRANT SELECT ON ref_dictionary, v_payments_current TO collector;
GRANT SELECT (client_id, last_name, first_name, middle_name, phone)
      ON client_personal TO collector;
GRANT SELECT (application_id, client_id) ON application TO collector;
GRANT SELECT (contract_id, application_id, contract_number, issue_date,
              loan_amount, term_months, outstanding_amount, status_ref_id)
      ON loan_contract TO collector;
GRANT UPDATE (status_ref_id) ON loan_contract TO collector;

-- 6. Аналитик данных
GRANT SELECT ON ref_dictionary, v_client_anon, client_financials, application,
      application_housing, loan_contract, collateral, previous_application,
      bureau, installments_payments TO data_analyst;

-- 7. Администратор БД (личная учётная запись admin_user в группе db_admin)
GRANT SELECT, INSERT, UPDATE, DELETE ON ref_dictionary TO db_admin;
GRANT SELECT ON audit_log TO security_officer;
GRANT pg_monitor TO db_admin;
GRANT db_admin TO admin_user;
ALTER ROLE admin_user CREATEROLE;
GRANT credit_manager, underwriter, collector, data_analyst, security_officer
      TO admin_user WITH ADMIN OPTION, INHERIT FALSE, SET FALSE;
GRANT schema_owner TO admin_user WITH INHERIT FALSE, SET TRUE;

-- 8. Служебные роли
GRANT pg_read_all_data TO backup_service;
GRANT EXECUTE ON FUNCTION fn_register_payment,
                          fn_purge_expired_data TO job_service;
```

Команды 3–8 выполняются владельцем схемы или суперпользователем при развёртывании. Функции создаются в `triggers_functions.sql`, представления в `roles.sql`, и те и другие до выдачи прав на них.

---

## 7. Обоснование выбора прав

1. **Группы вместо личных прав.** Права выдаются ролям, а не людям. Сотрудников много, должности меняются, а набор прав на должность остаётся прежним.
2. **Минимум привилегий (БП-1).** Каждая роль получает только таблицы и столбцы, нужные для её функции. Права на уровне столбцов закрывают то, что нельзя показывать целиком: ставку для взыскания, паспорт и адрес в `client_personal`, скоринг для менеджера.
3. **Представления вместо доступа к таблицам.** Обезличивание аналитика и фильтр «платежи только по текущим договорам» реализованы представлениями: пользователь видит только то, что включено в представление.
4. **Разделение обязанностей (БП-3).** Менеджер оформляет, андеррайтер решает, администратор управляет доступом, служба безопасности читает журнал. Ни одна роль не замыкает процесс на себе.
5. **Запись только через функции.** Платежи вносит `fn_register_payment`, журнал пишут триггеры, данные по сроку удаляет `fn_purge_expired_data`. Прямых `INSERT` и `DELETE` на эти таблицы нет, поэтому правила проверяются в одном месте и не обходятся.
6. **Администратор без прав на данные.** Его членство в группах выдано без наследования, поэтому он назначает людей в роли, но не получает их привилегий.
7. **Владелец отдельно.** Владелец объектов не совпадает ни с администратором, ни с пользователями. Утечка учётной записи сотрудника не даёт прав владельца.
8. **Закрытие умолчаний PostgreSQL.** По умолчанию `PUBLIC` может подключаться к базе и исполнять функции. Эти права отозваны, иначе матрица доступа обходилась бы через `PUBLIC`.

---

## 8. Проверка запретов

Эти проверки подтверждают, что запрещённые операции недоступны (материал для этапа 5 и для защиты).

| Под какой ролью | Команда | Ожидаемый результат |
|---|---|---|
| `data_analyst` | `SELECT * FROM client_personal;` | `permission denied for table client_personal` |
| `data_analyst` | `SELECT * FROM client;` | `permission denied for table client` |
| `data_analyst` | `SELECT * FROM v_client_anon LIMIT 5;` | строки без `birth_year` и профессий в исходном виде |
| `collector` | `SELECT passport_no FROM client_personal;` | `permission denied for table client_personal` |
| `collector` | `SELECT * FROM loan_contract;` | `permission denied` (нет права на `interest_rate`) |
| `credit_manager` | `DELETE FROM application;` | `permission denied for table application` |
| `credit_manager` | `UPDATE application SET target = 1;` | `permission denied for table application` |
| `underwriter` | `INSERT INTO installments_payments (...) VALUES (...);` | `permission denied for table installments_payments` |
| `security_officer` | `SELECT * FROM client;` | `permission denied for table client` |
| любая бизнес-роль | `INSERT INTO audit_log (...) VALUES (...);` | `permission denied for table audit_log` |
| `db_admin` | `SELECT * FROM loan_contract;` | `permission denied for table loan_contract` |

---

## 9. Допущения

1. Схема называется `credit`, база `credit_db`; имена уточняются по `schema.sql`.
2. Приём платежей выполняет `job_service` через `fn_register_payment` (например, по реестру платежей из платёжной системы); отдельной роли кассира в проекте нет.
3. `backup_service` читает все данные, включая ПДн (раздел 5.3).
4. Права рассчитаны на PostgreSQL 16 и выше; для более ранних версий схема членства в ролях требует пересмотра.
