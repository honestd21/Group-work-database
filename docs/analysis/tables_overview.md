# Сущности и атрибуты: обзор таблиц

Схема из 13 таблиц построена по датасету Home Credit Default Risk. Названия столбцов и типы согласованы с `schema.sql`. Карта данных (источник, пример значения, категория ПДн): `data_map.md`. Правила генерации синтетики: `docs/synthetic_data.md`.

Обозначения в таблицах столбцов: **Обяз.** — столбец `NOT NULL`; **Уник.** — `PK` (первичный ключ) или `UNIQUE`; **Ссылка** — внешний ключ (`FK`) на другую таблицу. Пометка «синт.» означает, что в датасете такого поля нет и значение генерируется.

---

## 1. Сводка таблиц и связей

| № | Таблица | Назначение | PK | Группа |
|---|---------|------------|----|--------|
| 1 | `client` | Заёмщик: обезличенные демографические признаки | `client_id` | Клиент |
| 2 | `client_personal` | Персональные данные заёмщика (ФИО, паспорт, контакты) | `client_id` | Клиент |
| 3 | `client_financials` | Выручка и чистая прибыль заёмщика по годам | `(client_id, fiscal_year)` | Клиент |
| 4 | `application` | Текущая заявка на кредит | `application_id` | Заявка и договор |
| 5 | `application_housing` | Характеристики жилья по заявке | `application_id` | Заявка и договор |
| 6 | `loan_contract` | Кредитный договор по заявке | `contract_id` | Заявка и договор |
| 7 | `collateral` | Обеспечение (залог) по договору | `collateral_id` | Заявка и договор |
| 8 | `guarantor` | Поручитель по договору | `guarantor_id` | Заявка и договор |
| 9 | `previous_application` | Прошлые заявки клиента в Home Credit | `prev_application_id` | Кредитная история |
| 10 | `bureau` | Кредиты клиента в других организациях | `bureau_id` | Кредитная история |
| 11 | `installments_payments` | Платежи по кредитам: прошлым (`previous_application`) и текущим (`loan_contract`) | `payment_id` | Платежи |
| 12 | `audit_log` | Журнал изменений таблиц с ПДн и коммерческой тайной | `audit_id` | Служебные |
| 13 | `ref_dictionary` | Единый справочник категориальных значений | `ref_id` | Служебные |

**Связи и мощности:**

| Родитель | Потомок | Мощность | Комментарий |
|----------|---------|----------|-------------|
| `client` | `client_personal` | 1 : 1 | у каждого клиента ровно одна запись ПДн |
| `client` | `client_financials` | 1 : N | по одной записи на каждый год |
| `client` | `application` | 1 : N | клиент может подавать несколько заявок |
| `application` | `application_housing` | 1 : 1 | жильё описывается в рамках заявки |
| `application` | `loan_contract` | 1 : 0..1 | каждая заявка из `application_train` — выданный кредит, поэтому договор создаётся для каждой |
| `loan_contract` | `collateral` | 1 : N | у договора может быть несколько предметов залога |
| `loan_contract` | `guarantor` | 1 : N | у договора может быть несколько поручителей |
| `client` | `previous_application` | 1 : N | история обращений в Home Credit |
| `client` | `bureau` | 1 : N | кредиты в других организациях |
| `previous_application` | `installments_payments` | 1 : N | платежи по одобренным прошлым кредитам; у платежа либо этот родитель, либо договор |
| `loan_contract` | `installments_payments` | 1 : N | платежи по текущему договору (синт.); у платежа либо этот родитель, либо прошлая заявка |
| `ref_dictionary` | многие таблицы | 1 : N | категории по `ref_id` |
| `audit_log` | — | без связей | связей с таблицами нет намеренно: журнал должен сохраняться, даже если запись в основной таблице удалена |

---

## 2. Описание таблиц

### 2.1. `client` — заёмщик

**Назначение.** Центральная сущность. В датасете нет идентификатора клиента (`SK_ID_CURR` — идентификатор заявки), поэтому клиент выделен в отдельную таблицу с собственным ключом. Хранит только обезличенные признаки: прямые идентификаторы вынесены в `client_personal`.
**Первичный ключ:** `client_id`.
**Ключевые атрибуты:** `client_type_ref_id`, `birth_year`, `education_ref_id`, `income_type_ref_id`.

| Столбец | Тип | Обяз. | Уник. | Ссылка | Комментарий |
|---------|-----|-------|-------|--------|-------------|
| `client_id` | `INT GENERATED ALWAYS AS IDENTITY` | да | PK | — | синт., суррогатный ключ |
| `client_type_ref_id` | `INT` | да | — | `ref_dictionary` | физлицо / ИП; синт., правило задано в synthetic_data.md |
| `gender` | `CHAR(1)` | да | — | — | `CHECK (gender IN ('M','F'))`; `CODE_GENDER`, значение `XNA` исключено |
| `birth_year` | `SMALLINT` | да | — | — | `CHECK (birth_year BETWEEN 1920 AND 2008)`; из `DAYS_BIRTH` и опорной даты, полная дата рождения не хранится |
| `education_ref_id` | `INT` | да | — | `ref_dictionary` | `NAME_EDUCATION_TYPE` |
| `family_status_ref_id` | `INT` | да | — | `ref_dictionary` | `NAME_FAMILY_STATUS` |
| `income_type_ref_id` | `INT` | да | — | `ref_dictionary` | `NAME_INCOME_TYPE` |
| `occupation_ref_id` | `INT` | нет | — | `ref_dictionary` | `OCCUPATION_TYPE`; в датасете много пропусков, поэтому допускает `NULL` |
| `cnt_children` | `SMALLINT` | да | — | — | `CHECK (cnt_children >= 0)`; `CNT_CHILDREN` |
| `own_car` | `BOOLEAN` | да | — | — | `FLAG_OWN_CAR` |
| `own_realty` | `BOOLEAN` | да | — | — | `FLAG_OWN_REALTY` |
| `created_at` | `DATE DEFAULT current_date` | да | — | — | синт., дата регистрации клиента |

### 2.2. `client_personal` — персональные данные

**Назначение.** Хранит прямые идентификаторы заёмщика. Вынесена отдельно, чтобы права на эту таблицу можно было выдавать отдельно (152-ФЗ): аналитик к ней доступа не имеет.
**Первичный ключ:** `client_id` (он же внешний ключ на `client`, связь 1 : 1).
**Ключевые атрибуты:** `last_name`, `first_name`, `passport_no`, `phone`.

| Столбец | Тип | Обяз. | Уник. | Ссылка | Комментарий |
|---------|-----|-------|-------|--------|-------------|
| `client_id` | `INT` | да | PK | `client` | `ON DELETE CASCADE` |
| `last_name` | `VARCHAR(60)` | да | — | — | синт. (Faker, `ru_RU`) |
| `first_name` | `VARCHAR(60)` | да | — | — | синт. |
| `middle_name` | `VARCHAR(60)` | нет | — | — | синт., отчество может отсутствовать |
| `passport_no` | `CHAR(10)` | да | `UNIQUE` | — | `CHECK (passport_no ~ '^[0-9]{10}$')`; серия и номер; синт. |
| `phone` | `VARCHAR(16)` | да | — | — | `CHECK (phone ~ '^\+7[0-9]{10}$')`; синт. |
| `email` | `VARCHAR(254)` | нет | `UNIQUE` | — | синт. |
| `registration_address` | `TEXT` | да | — | — | синт. |

### 2.3. `client_financials` — финансовые показатели по годам

**Назначение.** Выручка и чистая прибыль заёмщика за каждый год. На них опираются проверка «сумма кредита не больше 50 % выручки за прошлый год», расчёт уровня риска (долг к выручке) и ТОП заёмщиков по прибыли. В проекте хранится один финансовый год, 2025: заявки и договоры датируются 2026 годом, поэтому «прошлый год» для проверки это 2025.
**Первичный ключ:** составной `(client_id, fiscal_year)`.
**Ключевые атрибуты:** `fiscal_year`, `revenue`, `net_profit`.

| Столбец | Тип | Обяз. | Уник. | Ссылка | Комментарий |
|---------|-----|-------|-------|--------|-------------|
| `client_id` | `INT` | да | PK (часть) | `client` | `ON DELETE CASCADE` |
| `fiscal_year` | `SMALLINT` | да | PK (часть) | — | `CHECK (fiscal_year BETWEEN 2000 AND 2100)` |
| `revenue` | `NUMERIC(14,2)` | да | — | — | `CHECK (revenue >= 0)`; синт., от `AMT_INCOME_TOTAL`, не меньше 2 × `loan_amount` |
| `net_profit` | `NUMERIC(14,2)` | да | — | — | `CHECK (net_profit <= revenue)`; может быть отрицательной; синт. |

### 2.4. `application` — текущая заявка

**Назначение.** Заявка на кредит с анкетными данными и целевым признаком. Одна строка соответствует одной строке `application_train.csv`.
**Первичный ключ:** `application_id` (значение `SK_ID_CURR`).
**Ключевые атрибуты:** `client_id`, `contract_type_ref_id`, `amt_income_total`, `amt_credit`, `target`.

| Столбец | Тип | Обяз. | Уник. | Ссылка | Комментарий |
|---------|-----|-------|-------|--------|-------------|
| `application_id` | `INT` | да | PK | — | `SK_ID_CURR` |
| `client_id` | `INT` | да | — | `client` | синт., распределение заявок по клиентам |
| `contract_type_ref_id` | `INT` | да | — | `ref_dictionary` | `NAME_CONTRACT_TYPE` (Cash / Revolving) |
| `application_date` | `DATE` | да | — | — | синт., от опорной даты |
| `amt_income_total` | `NUMERIC(14,2)` | да | — | — | `CHECK (amt_income_total > 0)` |
| `amt_credit` | `NUMERIC(14,2)` | да | — | — | `CHECK (amt_credit > 0)` |
| `amt_annuity` | `NUMERIC(12,2)` | нет | — | — | `CHECK (amt_annuity > 0)`; есть пропуски |
| `amt_goods_price` | `NUMERIC(14,2)` | нет | — | — | `CHECK (amt_goods_price > 0)`; есть пропуски |
| `cnt_fam_members` | `SMALLINT` | нет | — | — | `CHECK (cnt_fam_members >= 1)` |
| `region_rating` | `SMALLINT` | да | — | — | `CHECK (region_rating IN (1,2,3))`; `REGION_RATING_CLIENT` |
| `region_population_relative` | `NUMERIC(9,6)` | нет | — | — | `CHECK (region_population_relative BETWEEN 0 AND 1)` |
| `ext_source_1` | `NUMERIC(10,9)` | нет | — | — | `CHECK (... BETWEEN 0 AND 1)`; внешний скоринговый балл |
| `ext_source_2` | `NUMERIC(10,9)` | нет | — | — | то же |
| `ext_source_3` | `NUMERIC(10,9)` | нет | — | — | то же |
| `bureau_enquiries_cnt` | `SMALLINT` | нет | — | — | `CHECK (bureau_enquiries_cnt >= 0)`; `AMT_REQ_CREDIT_BUREAU_YEAR` |
| `target` | `SMALLINT` | да | — | — | `CHECK (target IN (0,1))`; 1 — проблемы с платежами |

### 2.5. `application_housing` — жильё по заявке

**Назначение.** Урезанный набор характеристик жилья (около 10 из 47 исходных столбцов). Отдельная таблица, потому что эти поля описывают жильё, а не заявку, и в датасете сильно разрежены.
**Первичный ключ:** `application_id` (он же внешний ключ на `application`, связь 1 : 1).

| Столбец | Тип | Обяз. | Уник. | Ссылка | Комментарий |
|---------|-----|-------|-------|--------|-------------|
| `application_id` | `INT` | да | PK | `application` | `ON DELETE CASCADE` |
| `housing_type_ref_id` | `INT` | нет | — | `ref_dictionary` | `NAME_HOUSING_TYPE` |
| `walls_material_ref_id` | `INT` | нет | — | `ref_dictionary` | `WALLSMATERIAL_MODE` |
| `house_type_ref_id` | `INT` | нет | — | `ref_dictionary` | `HOUSETYPE_MODE` |
| `apartments_avg` | `NUMERIC(6,4)` | нет | — | — | `CHECK (... BETWEEN 0 AND 1)`; нормированное значение |
| `living_area_avg` | `NUMERIC(6,4)` | нет | — | — | то же |
| `total_area_mode` | `NUMERIC(6,4)` | нет | — | — | то же |
| `floors_max_avg` | `NUMERIC(6,4)` | нет | — | — | то же |
| `elevators_avg` | `NUMERIC(6,4)` | нет | — | — | то же |
| `years_build_avg` | `NUMERIC(6,4)` | нет | — | — | то же |
| `emergency_state` | `BOOLEAN` | нет | — | — | `EMERGENCYSTATE_MODE` (Yes/No → `TRUE/FALSE`) |

### 2.6. `loan_contract` — кредитный договор

**Назначение.** Договор по выданному кредиту: сумма, срок, ставка, остаток долга. Нужен для проверок по выручке и обеспечению и для расчёта непогашенной суммы. Платежи по договору хранятся в `installments_payments` (столбец `contract_id`).
**Первичный ключ:** `contract_id`.
**Ключевые атрибуты:** `application_id`, `contract_number`, `loan_amount`, `outstanding_amount`, `status_ref_id`.

| Столбец | Тип | Обяз. | Уник. | Ссылка | Комментарий |
|---------|-----|-------|-------|--------|-------------|
| `contract_id` | `INT GENERATED ALWAYS AS IDENTITY` | да | PK | — | синт. |
| `application_id` | `INT` | да | `UNIQUE` | `application` | один договор на заявку |
| `contract_number` | `VARCHAR(20)` | да | `UNIQUE` | — | синт., бизнес-идентификатор |
| `issue_date` | `DATE` | да | — | — | синт., после даты заявки |
| `loan_amount` | `NUMERIC(14,2)` | да | — | — | `CHECK (loan_amount > 0)`; копия `application.amt_credit`, фиксируется при подписании договора |
| `interest_rate` | `NUMERIC(5,2)` | да | — | — | `CHECK (interest_rate BETWEEN 0 AND 100)`; синт. |
| `term_months` | `SMALLINT` | да | — | — | `CHECK (term_months > 0)`; из `AMT_CREDIT / AMT_ANNUITY` |
| `outstanding_amount` | `NUMERIC(14,2)` | да | — | — | `CHECK (outstanding_amount >= 0 AND outstanding_amount <= loan_amount)`; синт. |
| `status_ref_id` | `INT` | да | — | `ref_dictionary` | действует / закрыт / просрочен; синт. |

### 2.7. `collateral` — обеспечение

**Назначение.** Предметы залога по договору. Нужна для проверки «стоимость обеспечения меньше 80 % суммы кредита».
**Первичный ключ:** `collateral_id`.
**Ключевые атрибуты:** `contract_id`, `collateral_type_ref_id`, `appraised_value`.

| Столбец | Тип | Обяз. | Уник. | Ссылка | Комментарий |
|---------|-----|-------|-------|--------|-------------|
| `collateral_id` | `INT GENERATED ALWAYS AS IDENTITY` | да | PK | — | синт. |
| `contract_id` | `INT` | да | — | `loan_contract` | `ON DELETE CASCADE` |
| `collateral_type_ref_id` | `INT` | да | — | `ref_dictionary` | недвижимость, автомобиль, депозит и др.; синт. |
| `appraised_value` | `NUMERIC(14,2)` | да | — | — | `CHECK (appraised_value > 0)`; синт., формула от `AMT_GOODS_PRICE` |
| `appraisal_date` | `DATE` | да | — | — | синт. |

### 2.8. `guarantor` — поручитель

**Назначение.** Поручитель по договору. Содержит ПДн третьего лица, поэтому, как и `client_personal`, закрыта от аналитика.
**Первичный ключ:** `guarantor_id`.
**Ключевые атрибуты:** `contract_id`, `passport_no`, `relation_ref_id`.

| Столбец | Тип | Обяз. | Уник. | Ссылка | Комментарий |
|---------|-----|-------|-------|--------|-------------|
| `guarantor_id` | `INT GENERATED ALWAYS AS IDENTITY` | да | PK | — | синт. |
| `contract_id` | `INT` | да | часть `UNIQUE` | `loan_contract` | `ON DELETE CASCADE` |
| `last_name` | `VARCHAR(60)` | да | — | — | синт. |
| `first_name` | `VARCHAR(60)` | да | — | — | синт. |
| `middle_name` | `VARCHAR(60)` | нет | — | — | синт. |
| `passport_no` | `CHAR(10)` | да | часть `UNIQUE` | — | `UNIQUE (contract_id, passport_no)`; формат как у `client_personal` |
| `phone` | `VARCHAR(16)` | да | — | — | синт. |
| `relation_ref_id` | `INT` | да | — | `ref_dictionary` | родственник, друг, коллега; синт. |

### 2.9. `previous_application` — прошлые заявки в Home Credit

**Назначение.** История обращений клиента в Home Credit, включая отказы и отменённые заявки. Именно здесь встречаются Consumer loans.
**Первичный ключ:** `prev_application_id` (значение `SK_ID_PREV`).
**Ключевые атрибуты:** `client_id`, `status_ref_id`, `decision_date`, `amt_credit`.

| Столбец | Тип | Обяз. | Уник. | Ссылка | Комментарий |
|---------|-----|-------|-------|--------|-------------|
| `prev_application_id` | `INT` | да | PK | — | `SK_ID_PREV` |
| `client_id` | `INT` | да | — | `client` | через `SK_ID_CURR` → заявка → клиент |
| `contract_type_ref_id` | `INT` | да | — | `ref_dictionary` | `NAME_CONTRACT_TYPE` (Cash / Consumer / Revolving) |
| `status_ref_id` | `INT` | да | — | `ref_dictionary` | `NAME_CONTRACT_STATUS` (одобрена, отказ, отменена, предложение не использовано) |
| `reject_reason_ref_id` | `INT` | нет | — | `ref_dictionary` | `CODE_REJECT_REASON`; заполнено только для отказов |
| `goods_category_ref_id` | `INT` | нет | — | `ref_dictionary` | `NAME_GOODS_CATEGORY` |
| `decision_date` | `DATE` | да | — | — | из `DAYS_DECISION` и опорной даты |
| `amt_application` | `NUMERIC(14,2)` | нет | — | — | `CHECK (amt_application >= 0)` |
| `amt_credit` | `NUMERIC(14,2)` | нет | — | — | `CHECK (amt_credit >= 0)` |
| `amt_annuity` | `NUMERIC(12,2)` | нет | — | — | `CHECK (amt_annuity >= 0)` |
| `cnt_payment` | `SMALLINT` | нет | — | — | `CHECK (cnt_payment > 0)`; плановое число платежей |

### 2.10. `bureau` — кредиты в других организациях

**Назначение.** Данные кредитного бюро: кредиты клиента в других банках. Влияют на оценку риска.
**Первичный ключ:** `bureau_id` (значение `SK_ID_BUREAU`).
**Ключевые атрибуты:** `client_id`, `credit_active_ref_id`, `amt_credit_sum_debt`, `credit_day_overdue`.

| Столбец | Тип | Обяз. | Уник. | Ссылка | Комментарий |
|---------|-----|-------|-------|--------|-------------|
| `bureau_id` | `INT` | да | PK | — | `SK_ID_BUREAU` |
| `client_id` | `INT` | да | — | `client` | через `SK_ID_CURR` → заявка → клиент |
| `credit_active_ref_id` | `INT` | да | — | `ref_dictionary` | `CREDIT_ACTIVE` |
| `credit_type_ref_id` | `INT` | да | — | `ref_dictionary` | `CREDIT_TYPE` |
| `date_open` | `DATE` | да | — | — | из `DAYS_CREDIT` и опорной даты |
| `date_end_planned` | `DATE` | нет | — | — | из `DAYS_CREDIT_ENDDATE`; есть пропуски |
| `amt_credit_sum` | `NUMERIC(14,2)` | нет | — | — | `CHECK (amt_credit_sum >= 0)` |
| `amt_credit_sum_debt` | `NUMERIC(14,2)` | нет | — | — | `CHECK (amt_credit_sum_debt >= 0)` |
| `amt_credit_sum_overdue` | `NUMERIC(14,2)` | нет | — | — | `CHECK (amt_credit_sum_overdue >= 0)` |
| `credit_day_overdue` | `INT` | да | — | — | `CHECK (credit_day_overdue >= 0)` |
| `cnt_credit_prolong` | `SMALLINT` | да | — | — | `CHECK (cnt_credit_prolong >= 0)` |

### 2.11. `installments_payments` — платежи по кредитам

**Назначение.** Плановые и фактические платежи по кредитам: по одобренным прошлым (данные датасета) и по текущим договорам (синтетика). Из сопоставления `due_date` и `payment_date` считается просрочка. Каждый платёж относится ровно к одному кредиту: либо к прошлой заявке, либо к текущему договору.
**Первичный ключ:** `payment_id` (суррогатный: в исходных данных составной ключ `SK_ID_PREV` + номер версии + номер платежа не гарантирует уникальность).
**Ключевые атрибуты:** `prev_application_id`, `contract_id`, `instalment_number`, `due_date`, `amt_instalment`, `amt_payment`.

| Столбец | Тип | Обяз. | Уник. | Ссылка | Комментарий |
|---------|-----|-------|-------|--------|-------------|
| `payment_id` | `BIGINT GENERATED ALWAYS AS IDENTITY` | да | PK | — | синт., таблица самая крупная |
| `prev_application_id` | `INT` | нет | — | `previous_application` | `SK_ID_PREV`; заполнено для платежей по прошлым кредитам, иначе `NULL` |
| `contract_id` | `INT` | нет | — | `loan_contract` | `ON DELETE CASCADE`; заполнено для платежей по текущему договору (синт.), иначе `NULL` |
| `instalment_version` | `SMALLINT` | да | — | — | `NUM_INSTALMENT_VERSION`; для синтетических платежей по договору всегда 1 |
| `instalment_number` | `SMALLINT` | да | — | — | `CHECK (instalment_number > 0)`; `NUM_INSTALMENT_NUMBER` |
| `due_date` | `DATE` | да | — | — | из `DAYS_INSTALMENT` и опорной даты; для договоров считается от `issue_date` |
| `payment_date` | `DATE` | нет | — | — | из `DAYS_ENTRY_PAYMENT`; `NULL`, если платёж не внесён |
| `amt_instalment` | `NUMERIC(12,2)` | да | — | — | `CHECK (amt_instalment >= 0)` |
| `amt_payment` | `NUMERIC(12,2)` | нет | — | — | `CHECK (amt_payment >= 0)`; `NULL`, если платёж не внесён |

**Ограничение на принадлежность платежа.** Заполнено ровно одно из полей `prev_application_id` и `contract_id`:

```sql
CONSTRAINT chk_payment_one_parent
    CHECK (num_nonnulls(prev_application_id, contract_id) = 1)
```

Клиент определяется через `previous_application.client_id` (прошлые кредиты) или через `loan_contract` → `application.client_id` (текущие договоры).

### 2.12. `audit_log` — журнал аудита

**Назначение.** Хранит историю изменений таблиц с ПДн и коммерческой тайной: кто, когда, какая таблица, какая операция, старые и новые данные. Заполняется триггерами (разработка триггеров — зона администратора).
**Первичный ключ:** `audit_id`.
**Ключевые атрибуты:** `table_name`, `operation`, `db_user`, `changed_at`, `old_data`, `new_data`.

| Столбец | Тип | Обяз. | Уник. | Ссылка | Комментарий |
|---------|-----|-------|-------|--------|-------------|
| `audit_id` | `BIGINT GENERATED ALWAYS AS IDENTITY` | да | PK | — | |
| `table_name` | `VARCHAR(63)` | да | — | — | имя таблицы (максимальная длина идентификатора в PostgreSQL) |
| `operation` | `VARCHAR(6)` | да | — | — | `CHECK (operation IN ('INSERT','UPDATE','DELETE'))` |
| `record_pk` | `TEXT` | нет | — | — | значение ключа изменённой записи |
| `db_user` | `VARCHAR(63)` | да | — | — | `DEFAULT current_user` |
| `changed_at` | `TIMESTAMPTZ` | да | — | — | `DEFAULT now()` |
| `old_data` | `JSONB` | нет | — | — | состояние до изменения; для `INSERT` пусто |
| `new_data` | `JSONB` | нет | — | — | состояние после изменения; для `DELETE` пусто; `CHECK (old_data IS NOT NULL OR new_data IS NOT NULL)` |

### 2.13. `ref_dictionary` — единый справочник

**Назначение.** Хранит все категориальные значения (образование, семейное положение, тип договора и др.) в одной таблице вместо повторяющихся текстовых строк в основных таблицах.
**Первичный ключ:** `ref_id`.
**Ключевые атрибуты:** `category`, `code`.

| Столбец | Тип | Обяз. | Уник. | Ссылка | Комментарий |
|---------|-----|-------|-------|--------|-------------|
| `ref_id` | `INT GENERATED ALWAYS AS IDENTITY` | да | PK | — | |
| `category` | `VARCHAR(40)` | да | часть `UNIQUE` | — | группа значений, например `education`, `family_status` |
| `code` | `VARCHAR(80)` | да | часть `UNIQUE` | — | значение из датасета, например `Secondary / secondary special`; `UNIQUE (category, code)` |
| `description` | `VARCHAR(200)` | нет | — | — | пояснение |

Категории: `client_type`, `education`, `family_status`, `income_type`, `occupation`, `contract_type`, `housing_type`, `walls_material`, `house_type`, `loan_status`, `collateral_type`, `guarantor_relation`, `credit_active`, `credit_type`, `prev_contract_status`, `reject_reason`, `goods_category`.

**Ограничение единого справочника.** Внешний ключ проверяет только то, что `ref_id` существует, но не то, что запись относится к нужной категории (в `education_ref_id` можно записать значение категории `credit_type`). Контроль категории возможен через составной внешний ключ `(ref_id, category)` или триггер; в проекте этот контроль не реализован: справочник заполняется скриптом генерации из значений датасета, поэтому ссылки на чужие категории не возникают.

---

## 3. Индексы

PostgreSQL автоматически создаёт индексы для `PRIMARY KEY` и `UNIQUE`, но **не** для внешних ключей, поэтому индексы по столбцам-ссылкам создаются явно. Столбцы `*_ref_id` в справочник не индексируются: значений мало, планировщик всё равно выберет последовательное чтение.

| № | Индекс | Тип | Таблица (столбцы) | Зачем |
|---|--------|-----|-------------------|-------|
| 1 | `idx_application_client_id` | B-tree | `application (client_id)` | соединение заявок с клиентом, выборка заявок клиента |
| 2 | `idx_client_fin_year_profit` | B-tree | `client_financials (fiscal_year, net_profit DESC)` | ТОП заёмщиков по чистой прибыли за год |
| 3 | `idx_collateral_contract_id` | B-tree | `collateral (contract_id)` | суммирование обеспечения по договору |
| 4 | `idx_loan_contract_status` | B-tree | `loan_contract (status_ref_id, issue_date)` | выборка договоров по статусу и периоду |
| 5 | `idx_prev_application_client_id` | B-tree | `previous_application (client_id)` | история обращений клиента |
| 6 | `idx_bureau_client_id` | B-tree | `bureau (client_id)` | кредиты клиента в бюро |
| 7 | `idx_installments_prev_app` | B-tree | `installments_payments (prev_application_id, instalment_number)` | платежи по кредиту в порядке номеров |
| 8 | `idx_audit_changed_brin` | BRIN | `audit_log (changed_at)` | журнал дописывается по времени, данные физически упорядочены, индекс занимает килобайты |
| 9 | `idx_audit_new_data_gin` | GIN (`jsonb_path_ops`) | `audit_log (new_data)` | поиск по содержимому JSON |
| 10 | `idx_installments_contract` | B-tree, частичный | `installments_payments (contract_id, instalment_number) WHERE contract_id IS NOT NULL` | платежи по договору в порядке номеров, просрочки по текущим договорам; строки с `NULL` в индекс не попадают |

```sql
CREATE INDEX idx_application_client_id      ON application (client_id);
CREATE INDEX idx_client_fin_year_profit     ON client_financials (fiscal_year, net_profit DESC);
CREATE INDEX idx_collateral_contract_id     ON collateral (contract_id);
CREATE INDEX idx_loan_contract_status       ON loan_contract (status_ref_id, issue_date);
CREATE INDEX idx_prev_application_client_id ON previous_application (client_id);
CREATE INDEX idx_bureau_client_id           ON bureau (client_id);
CREATE INDEX idx_installments_prev_app      ON installments_payments (prev_application_id, instalment_number);
CREATE INDEX idx_audit_changed_brin         ON audit_log USING BRIN (changed_at);
CREATE INDEX idx_audit_new_data_gin         ON audit_log USING GIN (new_data jsonb_path_ops);
CREATE INDEX idx_installments_contract      ON installments_payments (contract_id, instalment_number)
    WHERE contract_id IS NOT NULL;
```

---

## 4. Обоснование типов данных

| Тип | Где используется | Почему |
|-----|------------------|--------|
| `NUMERIC(p,2)` | суммы, выручка, прибыль, остаток долга | деньги требуют точной десятичной арифметики; `REAL/DOUBLE PRECISION` дают ошибки округления, тип `MONEY` привязан к локали |
| `NUMERIC(p,s)` с `CHECK` | скоринговые баллы, нормированные характеристики жилья | значения в диапазоне 0–1, нужна фиксированная точность |
| `DATE` | даты заявок, решений, платежей | в источнике это смещения в днях (`DAYS_*`), которые пересчитываются в даты от опорной даты; время суток не нужно |
| `TIMESTAMPTZ` | `audit_log.changed_at` | для журнала важен момент события с учётом часового пояса |
| `INT` | идентификаторы (`SK_ID_CURR`, `SK_ID_PREV`, `SK_ID_BUREAU`, суррогатные ключи) | значения не превышают нескольких миллионов, диапазон `INT` достаточен |
| `BIGINT` | `payment_id`, `audit_id` | таблицы самые крупные и растущие |
| `SMALLINT` | счётчики, годы, номера платежей, флаги `0/1` | малый диапазон, экономия места |
| `BOOLEAN` | `own_car`, `own_realty`, `emergency_state` | двоичные признаки; в источнике хранятся как `Y/N` или `Yes/No` |
| `CHAR(n)` | `gender`, `passport_no` | значения фиксированной длины |
| `VARCHAR(n)` | ФИО, телефон, email, коды справочника | есть разумный предел длины, `CHECK` и ограничение длины защищают от мусора |
| `TEXT` | `registration_address`, `record_pk` | длина не ограничена |
| `JSONB` | `audit_log.old_data`, `new_data` | снимок строки с произвольным набором полей; поддерживает GIN-индекс |
| `GENERATED ALWAYS AS IDENTITY` | суррогатные ключи | стандартный SQL-способ, предпочтительнее `SERIAL` |

Идентификаторы датасета (`SK_ID_CURR`, `SK_ID_PREV`, `SK_ID_BUREAU`) сохранены как есть: это упрощает сверку загруженных данных с исходными CSV.

---

## 5. Нормализация: нарушения в исходных CSV и их устранение

| Нормальная форма | Нарушение в датасете | Как исправлено |
|------------------|----------------------|----------------|
| **1НФ** (атомарность, нет повторяющихся групп) | Группы столбцов `*_AVG`, `*_MODE`, `*_MEDI` — три версии одного показателя; блок флагов `FLAG_DOCUMENT_2…21` | В `application_housing` оставлена одна версия показателей; таблица документов в схему не включена |
| **1НФ** | Значения в разных единицах и служебные заглушки: смещения в днях (`DAYS_*`), `XNA`, `365243` в `DAYS_EMPLOYED` | Смещения пересчитаны в `DATE`; заглушки заменены на `NULL` или отброшены |
| **2НФ** (нет частичных зависимостей от составного ключа) | `installments_payments`: ключ составной (`SK_ID_PREV`, версия, номер платежа) | Введён суррогатный ключ `payment_id`; атрибуты зависят от всей строки платежа |
| **3НФ** (нет транзитивных зависимостей) | В `application` признаки клиента (пол, образование, семейное положение, занятость) зависят от клиента, а не от заявки | Вынесены в `client` |
| **3НФ** | В `installments_payments` есть `SK_ID_CURR`, который определяется через `SK_ID_PREV` → заявка → клиент | `client_id` убран из таблицы платежей; клиент определяется через `previous_application` или через `loan_contract` → `application` |
| **3НФ** | Нужно хранить платежи по двум видам кредитов: прошлым и текущим | Платёж — одна сущность, поэтому одна таблица. Принадлежность задаётся двумя необязательными внешними ключами и `CHECK` «ровно один из двух» |
| **3НФ** | Текстовые категории повторяются в сотнях тысяч строк (`NAME_EDUCATION_TYPE`, `NAME_CONTRACT_STATUS` и др.) | Значения вынесены в `ref_dictionary`, в таблицах хранится `ref_id` |
| **3НФ** | Персональные данные смешаны с анкетными признаками | Вынесены в `client_personal` (и `guarantor` для третьих лиц) |

---

