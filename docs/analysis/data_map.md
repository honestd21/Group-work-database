# Карта данных (13 таблиц)

Карта данных — реестр всех атрибутов схемы: откуда взято значение, какой у него тип, обязательно ли оно, уникально ли и к какой категории защиты относится. Названия таблиц, столбцов и типов согласованы с `tables_overview.md`.

## Легенда

- **Обязательность:** «Да», если в схеме стоит `NOT NULL` (или атрибут входит в PK).
- **Уникальность:** «Да», если атрибут PK или имеет `UNIQUE`. «Да (в составе PK)» или «Да (в составе UNIQUE)» значит, что уникальна только комбинация столбцов.
- **Примечание (категория):**
  - **ПДн** (152-ФЗ): данные, по которым можно определить физическое лицо.
  - **Коммерческая тайна:** финансовые и скоринговые данные компании и клиентов (суммы, ставки, выручка, оценки, статусы, платежи).
  - **Открытые:** идентификаторы без ПДн и значения справочников.
  - **Открытые (косвенный идентификатор):** сами по себе не раскрывают человека, но в сочетании друг с другом (год рождения, пол, профессия) могут его идентифицировать. Доступ к ним нужно ограничивать так же аккуратно.
- **Источник:** имя CSV-файла датасета Home Credit (в скобках исходный столбец), либо «Синтетика» (генерируется нами, формулы и seed в `docs/synthetic_data.md`), либо «Служебное» (создаётся самой БД).
- Типы `INT (FK)` означают внешний ключ. Столбцы `*_ref_id` ссылаются на `ref_dictionary`, в примерах указан условный `ref_id`; значения подобраны так, чтобы разные категории не пересекались (например, `ref_id = 3` это образование «Secondary / secondary special», как в `client.education_ref_id`).
- Даты в CSV заданы смещением в днях (например, `DAYS_DECISION = -73`). Они пересчитываются в `DATE` от опорной даты, которую задаём в `docs/synthetic_data.md`.
- Примеры значений типичные. Значения из CSV нужно сверить с реальными строками загруженных файлов.

---


## 1. `ref_dictionary`

| Источник данных | Сущность | Атрибут | Тип данных | Пример значения | Обязательность | Уникальность | Примечание |
|---|---|---|---|---|---|---|---|
| Служебное (генерируется БД) | `ref_dictionary` | `ref_id` | `INT GENERATED ALWAYS AS IDENTITY` | 3 | Да | Да | Открытые |
| Задаётся вручную (виды справочников) | `ref_dictionary` | `category` | `VARCHAR(40)` | education | Да | Да (в паре с `code`) | Открытые |
| Категориальные столбцы CSV | `ref_dictionary` | `code` | `VARCHAR(80)` | Secondary / secondary special | Да | Да (в паре с `category`) | Открытые |
| Перевод вручную | `ref_dictionary` | `description` | `VARCHAR(200)` | Среднее специальное образование | Нет | Нет | Открытые |

## 2. `client`

| Источник данных | Сущность | Атрибут | Тип данных | Пример значения | Обязательность | Уникальность | Примечание |
|---|---|---|---|---|---|---|---|
| Служебное (генерируется БД) | `client` | `client_id` | `INT GENERATED ALWAYS AS IDENTITY` | 1 | Да | Да | Открытые |
| Синтетика (правило задано в `synthetic_data.md`, исходный признак `NAME_INCOME_TYPE`) | `client` | `client_type_ref_id` | `INT (FK)` | 1 | Да | Нет | Открытые |
| `application_train.csv` (`CODE_GENDER`) | `client` | `gender` | `CHAR(1)` | F | Да | Нет | Открытые (косвенный идентификатор) |
| Синтетика (производное от `DAYS_BIRTH` и опорной даты) | `client` | `birth_year` | `SMALLINT` | 1989 | Да | Нет | Открытые (косвенный идентификатор) |
| `application_train.csv` (`NAME_EDUCATION_TYPE`) | `client` | `education_ref_id` | `INT (FK)` | 3 | Да | Нет | Открытые (косвенный идентификатор) |
| `application_train.csv` (`NAME_FAMILY_STATUS`) | `client` | `family_status_ref_id` | `INT (FK)` | 9 | Да | Нет | Открытые (косвенный идентификатор) |
| `application_train.csv` (`NAME_INCOME_TYPE`) | `client` | `income_type_ref_id` | `INT (FK)` | 12 | Да | Нет | Коммерческая тайна |
| `application_train.csv` (`OCCUPATION_TYPE`) | `client` | `occupation_ref_id` | `INT (FK)` | 21 | Нет | Нет | Открытые (косвенный идентификатор) |
| `application_train.csv` (`CNT_CHILDREN`) | `client` | `cnt_children` | `SMALLINT` | 0 | Да | Нет | Открытые (косвенный идентификатор) |
| `application_train.csv` (`FLAG_OWN_CAR`) | `client` | `own_car` | `BOOLEAN` | false | Да | Нет | Коммерческая тайна |
| `application_train.csv` (`FLAG_OWN_REALTY`) | `client` | `own_realty` | `BOOLEAN` | true | Да | Нет | Коммерческая тайна |
| Синтетика | `client` | `created_at` | `DATE` | 2025-01-15 | Да | Нет | Открытые |

## 3. `client_personal`

| Источник данных | Сущность | Атрибут | Тип данных | Пример значения | Обязательность | Уникальность | Примечание |
|---|---|---|---|---|---|---|---|
| Синтетика (ключ из `client`) | `client_personal` | `client_id` | `INT (PK, FK)` | 1 | Да | Да | Открытые (ключ связи), сама запись содержит ПДн |
| Синтетика (Faker, ru_RU) | `client_personal` | `last_name` | `VARCHAR(60)` | Иванов | Да | Нет | ПДн |
| Синтетика (Faker, ru_RU) | `client_personal` | `first_name` | `VARCHAR(60)` | Пётр | Да | Нет | ПДн |
| Синтетика (Faker, ru_RU) | `client_personal` | `middle_name` | `VARCHAR(60)` | Сергеевич | Нет | Нет | ПДн |
| Синтетика (Faker) | `client_personal` | `passport_no` | `CHAR(10)` | 4512345678 | Да | Да | ПДн |
| Синтетика (Faker) | `client_personal` | `phone` | `VARCHAR(16)` | +79161234567 | Да | Нет | ПДн |
| Синтетика (Faker) | `client_personal` | `email` | `VARCHAR(254)` | ivanov@example.com | Нет | Да | ПДн |
| Синтетика (Faker) | `client_personal` | `registration_address` | `TEXT` | г. Москва, ул. Ленина, д. 5, кв. 12 | Да | Нет | ПДн |

## 4. `client_financials`

| Источник данных | Сущность | Атрибут | Тип данных | Пример значения | Обязательность | Уникальность | Примечание |
|---|---|---|---|---|---|---|---|
| Синтетика (ключ из `client`) | `client_financials` | `client_id` | `INT (PK, FK)` | 1 | Да | Да (в составе PK) | Открытые |
| Синтетика | `client_financials` | `fiscal_year` | `SMALLINT (PK)` | 2025 | Да | Да (в составе PK) | Открытые |
| Синтетика (от `AMT_INCOME_TOTAL`, не меньше 2 × `loan_amount`) | `client_financials` | `revenue` | `NUMERIC(14,2)` | 2400000.00 | Да | Нет | Коммерческая тайна |
| Синтетика (формула от `revenue`) | `client_financials` | `net_profit` | `NUMERIC(14,2)` | 310000.00 | Да | Нет | Коммерческая тайна |

В проекте хранится один финансовый год, 2025. Заявки и договоры датируются 2026 годом, поэтому «прошлый год» для проверки «кредит не больше 50 % выручки» (триггер на `loan_contract`) это 2025.

## 5. `application`

| Источник данных | Сущность | Атрибут | Тип данных | Пример значения | Обязательность | Уникальность | Примечание |
|---|---|---|---|---|---|---|---|
| `application_train.csv` (`SK_ID_CURR`) | `application` | `application_id` | `INT` | 100002 | Да | Да | Открытые |
| Синтетика (распределение заявок по клиентам) | `application` | `client_id` | `INT (FK)` | 1 | Да | Нет | Открытые |
| `application_train.csv` (`NAME_CONTRACT_TYPE`) | `application` | `contract_type_ref_id` | `INT (FK)` | 5 | Да | Нет | Открытые |
| Синтетика (от опорной даты) | `application` | `application_date` | `DATE` | 2026-03-14 | Да | Нет | Коммерческая тайна |
| `application_train.csv` (`AMT_INCOME_TOTAL`) | `application` | `amt_income_total` | `NUMERIC(14,2)` | 202500.00 | Да | Нет | Коммерческая тайна |
| `application_train.csv` (`AMT_CREDIT`) | `application` | `amt_credit` | `NUMERIC(14,2)` | 406597.50 | Да | Нет | Коммерческая тайна |
| `application_train.csv` (`AMT_ANNUITY`) | `application` | `amt_annuity` | `NUMERIC(12,2)` | 24700.50 | Нет | Нет | Коммерческая тайна |
| `application_train.csv` (`AMT_GOODS_PRICE`) | `application` | `amt_goods_price` | `NUMERIC(14,2)` | 351000.00 | Нет | Нет | Коммерческая тайна |
| `application_train.csv` (`CNT_FAM_MEMBERS`) | `application` | `cnt_fam_members` | `SMALLINT` | 2 | Нет | Нет | Открытые (косвенный идентификатор) |
| `application_train.csv` (`REGION_RATING_CLIENT`) | `application` | `region_rating` | `SMALLINT` | 2 | Да | Нет | Открытые |
| `application_train.csv` (`REGION_POPULATION_RELATIVE`) | `application` | `region_population_relative` | `NUMERIC(9,6)` | 0.018801 | Нет | Нет | Открытые |
| `application_train.csv` (`EXT_SOURCE_1`) | `application` | `ext_source_1` | `NUMERIC(10,9)` | 0.083036967 | Нет | Нет | Коммерческая тайна |
| `application_train.csv` (`EXT_SOURCE_2`) | `application` | `ext_source_2` | `NUMERIC(10,9)` | 0.262948593 | Нет | Нет | Коммерческая тайна |
| `application_train.csv` (`EXT_SOURCE_3`) | `application` | `ext_source_3` | `NUMERIC(10,9)` | 0.139375748 | Нет | Нет | Коммерческая тайна |
| `application_train.csv` (`AMT_REQ_CREDIT_BUREAU_YEAR`) | `application` | `bureau_enquiries_cnt` | `SMALLINT` | 1 | Нет | Нет | Коммерческая тайна |
| `application_train.csv` (`TARGET`) | `application` | `target` | `SMALLINT` | 1 | Да | Нет | Коммерческая тайна |

В CSV нет столбца с датой подачи заявки, поэтому `application_date` генерируется от опорной даты (правило в `docs/synthetic_data.md`).

## 6. `application_housing`

| Источник данных | Сущность | Атрибут | Тип данных | Пример значения | Обязательность | Уникальность | Примечание |
|---|---|---|---|---|---|---|---|
| Синтетика (ключ из `application`) | `application_housing` | `application_id` | `INT (PK, FK)` | 100002 | Да | Да | Открытые |
| `application_train.csv` (`NAME_HOUSING_TYPE`) | `application_housing` | `housing_type_ref_id` | `INT (FK)` | 15 | Нет | Нет | Открытые (косвенный идентификатор) |
| `application_train.csv` (`WALLSMATERIAL_MODE`) | `application_housing` | `walls_material_ref_id` | `INT (FK)` | 22 | Нет | Нет | Открытые (косвенный идентификатор) |
| `application_train.csv` (`HOUSETYPE_MODE`) | `application_housing` | `house_type_ref_id` | `INT (FK)` | 18 | Нет | Нет | Открытые (косвенный идентификатор) |
| `application_train.csv` (`APARTMENTS_AVG`) | `application_housing` | `apartments_avg` | `NUMERIC(6,4)` | 0.0247 | Нет | Нет | Открытые |
| `application_train.csv` (`LIVINGAREA_AVG`) | `application_housing` | `living_area_avg` | `NUMERIC(6,4)` | 0.0190 | Нет | Нет | Открытые |
| `application_train.csv` (`TOTALAREA_MODE`) | `application_housing` | `total_area_mode` | `NUMERIC(6,4)` | 0.0149 | Нет | Нет | Открытые |
| `application_train.csv` (`FLOORSMAX_AVG`) | `application_housing` | `floors_max_avg` | `NUMERIC(6,4)` | 0.0833 | Нет | Нет | Открытые |
| `application_train.csv` (`ELEVATORS_AVG`) | `application_housing` | `elevators_avg` | `NUMERIC(6,4)` | 0.0000 | Нет | Нет | Открытые |
| `application_train.csv` (`YEARS_BUILD_AVG`) | `application_housing` | `years_build_avg` | `NUMERIC(6,4)` | 0.9722 | Нет | Нет | Открытые |
| `application_train.csv` (`EMERGENCYSTATE_MODE`) | `application_housing` | `emergency_state` | `BOOLEAN` | false | Нет | Нет | Открытые |

## 7. `loan_contract`

| Источник данных | Сущность | Атрибут | Тип данных | Пример значения | Обязательность | Уникальность | Примечание |
|---|---|---|---|---|---|---|---|
| Служебное (генерируется БД) | `loan_contract` | `contract_id` | `INT GENERATED ALWAYS AS IDENTITY` | 1 | Да | Да | Открытые |
| Синтетика (по каждой заявке из `application_train`) | `loan_contract` | `application_id` | `INT (FK)` | 100002 | Да | Да | Открытые |
| Синтетика | `loan_contract` | `contract_number` | `VARCHAR(20)` | LC-2026-000001 | Да | Да | Коммерческая тайна |
| Синтетика (после даты заявки) | `loan_contract` | `issue_date` | `DATE` | 2026-03-20 | Да | Нет | Коммерческая тайна |
| Синтетика (копия `AMT_CREDIT` заявки) | `loan_contract` | `loan_amount` | `NUMERIC(14,2)` | 406597.50 | Да | Нет | Коммерческая тайна |
| Синтетика | `loan_contract` | `interest_rate` | `NUMERIC(5,2)` | 14.90 | Да | Нет | Коммерческая тайна |
| Синтетика (из `AMT_CREDIT / AMT_ANNUITY`) | `loan_contract` | `term_months` | `SMALLINT` | 16 | Да | Нет | Коммерческая тайна |
| Синтетика (согласовано с платежами) | `loan_contract` | `outstanding_amount` | `NUMERIC(14,2)` | 210000.00 | Да | Нет | Коммерческая тайна |
| Синтетика | `loan_contract` | `status_ref_id` | `INT (FK)` | 61 | Да | Нет | Коммерческая тайна |

## 8. `collateral`

| Источник данных | Сущность | Атрибут | Тип данных | Пример значения | Обязательность | Уникальность | Примечание |
|---|---|---|---|---|---|---|---|
| Служебное (генерируется БД) | `collateral` | `collateral_id` | `INT GENERATED ALWAYS AS IDENTITY` | 1 | Да | Да | Открытые |
| Синтетика | `collateral` | `contract_id` | `INT (FK)` | 1 | Да | Нет | Открытые |
| Синтетика | `collateral` | `collateral_type_ref_id` | `INT (FK)` | 71 | Да | Нет | Коммерческая тайна |
| Синтетика (формула от `AMT_GOODS_PRICE`) | `collateral` | `appraised_value` | `NUMERIC(14,2)` | 450000.00 | Да | Нет | Коммерческая тайна |
| Синтетика | `collateral` | `appraisal_date` | `DATE` | 2026-03-18 | Да | Нет | Коммерческая тайна |

## 9. `guarantor`

| Источник данных | Сущность | Атрибут | Тип данных | Пример значения | Обязательность | Уникальность | Примечание |
|---|---|---|---|---|---|---|---|
| Служебное (генерируется БД) | `guarantor` | `guarantor_id` | `INT GENERATED ALWAYS AS IDENTITY` | 1 | Да | Да | Открытые (ключ), сама запись содержит ПДн |
| Синтетика | `guarantor` | `contract_id` | `INT (FK)` | 1 | Да | Да (в составе UNIQUE с `passport_no`) | Открытые |
| Синтетика (Faker, ru_RU) | `guarantor` | `last_name` | `VARCHAR(60)` | Петрова | Да | Нет | ПДн |
| Синтетика (Faker, ru_RU) | `guarantor` | `first_name` | `VARCHAR(60)` | Анна | Да | Нет | ПДн |
| Синтетика (Faker, ru_RU) | `guarantor` | `middle_name` | `VARCHAR(60)` | Ивановна | Нет | Нет | ПДн |
| Синтетика (Faker) | `guarantor` | `passport_no` | `CHAR(10)` | 4510987654 | Да | Да (в составе UNIQUE с `contract_id`) | ПДн |
| Синтетика (Faker) | `guarantor` | `phone` | `VARCHAR(16)` | +79257654321 | Да | Нет | ПДн |
| Синтетика | `guarantor` | `relation_ref_id` | `INT (FK)` | 81 | Да | Нет | ПДн (сведения о родстве) |

## 10. `previous_application`

| Источник данных | Сущность | Атрибут | Тип данных | Пример значения | Обязательность | Уникальность | Примечание |
|---|---|---|---|---|---|---|---|
| `previous_application.csv` (`SK_ID_PREV`) | `previous_application` | `prev_application_id` | `INT` | 2030495 | Да | Да | Открытые |
| `previous_application.csv` (`SK_ID_CURR`) → заявка → клиент | `previous_application` | `client_id` | `INT (FK)` | 1 | Да | Нет | Открытые |
| `previous_application.csv` (`NAME_CONTRACT_TYPE`) | `previous_application` | `contract_type_ref_id` | `INT (FK)` | 6 | Да | Нет | Открытые |
| `previous_application.csv` (`NAME_CONTRACT_STATUS`) | `previous_application` | `status_ref_id` | `INT (FK)` | 8 | Да | Нет | Коммерческая тайна |
| `previous_application.csv` (`CODE_REJECT_REASON`) | `previous_application` | `reject_reason_ref_id` | `INT (FK)` | 30 | Нет | Нет | Коммерческая тайна |
| `previous_application.csv` (`NAME_GOODS_CATEGORY`) | `previous_application` | `goods_category_ref_id` | `INT (FK)` | 10 | Нет | Нет | Открытые |
| `previous_application.csv` (`DAYS_DECISION`), пересчёт в дату | `previous_application` | `decision_date` | `DATE` | 2024-10-18 | Да | Нет | Коммерческая тайна |
| `previous_application.csv` (`AMT_APPLICATION`) | `previous_application` | `amt_application` | `NUMERIC(14,2)` | 17145.00 | Нет | Нет | Коммерческая тайна |
| `previous_application.csv` (`AMT_CREDIT`) | `previous_application` | `amt_credit` | `NUMERIC(14,2)` | 17145.00 | Нет | Нет | Коммерческая тайна |
| `previous_application.csv` (`AMT_ANNUITY`) | `previous_application` | `amt_annuity` | `NUMERIC(12,2)` | 1730.43 | Нет | Нет | Коммерческая тайна |
| `previous_application.csv` (`CNT_PAYMENT`) | `previous_application` | `cnt_payment` | `SMALLINT` | 12 | Нет | Нет | Коммерческая тайна |

## 11. `bureau`

| Источник данных | Сущность | Атрибут | Тип данных | Пример значения | Обязательность | Уникальность | Примечание |
|---|---|---|---|---|---|---|---|
| `bureau.csv` (`SK_ID_BUREAU`) | `bureau` | `bureau_id` | `INT` | 5714462 | Да | Да | Открытые |
| `bureau.csv` (`SK_ID_CURR`) → заявка → клиент | `bureau` | `client_id` | `INT (FK)` | 1 | Да | Нет | Открытые |
| `bureau.csv` (`CREDIT_ACTIVE`) | `bureau` | `credit_active_ref_id` | `INT (FK)` | 52 | Да | Нет | Коммерческая тайна |
| `bureau.csv` (`CREDIT_TYPE`) | `bureau` | `credit_type_ref_id` | `INT (FK)` | 40 | Да | Нет | Открытые |
| `bureau.csv` (`DAYS_CREDIT`), пересчёт в дату | `bureau` | `date_open` | `DATE` | 2023-06-02 | Да | Нет | Коммерческая тайна |
| `bureau.csv` (`DAYS_CREDIT_ENDDATE`), пересчёт в дату | `bureau` | `date_end_planned` | `DATE` | 2025-01-15 | Нет | Нет | Коммерческая тайна |
| `bureau.csv` (`AMT_CREDIT_SUM`) | `bureau` | `amt_credit_sum` | `NUMERIC(14,2)` | 91323.00 | Нет | Нет | Коммерческая тайна |
| `bureau.csv` (`AMT_CREDIT_SUM_DEBT`) | `bureau` | `amt_credit_sum_debt` | `NUMERIC(14,2)` | 0.00 | Нет | Нет | Коммерческая тайна |
| `bureau.csv` (`AMT_CREDIT_SUM_OVERDUE`) | `bureau` | `amt_credit_sum_overdue` | `NUMERIC(14,2)` | 0.00 | Нет | Нет | Коммерческая тайна |
| `bureau.csv` (`CREDIT_DAY_OVERDUE`) | `bureau` | `credit_day_overdue` | `INT` | 0 | Да | Нет | Коммерческая тайна |
| `bureau.csv` (`CNT_CREDIT_PROLONG`) | `bureau` | `cnt_credit_prolong` | `SMALLINT` | 0 | Да | Нет | Коммерческая тайна |

## 12. `installments_payments`

| Источник данных | Сущность | Атрибут | Тип данных | Пример значения | Обязательность | Уникальность | Примечание |
|---|---|---|---|---|---|---|---|
| Служебное (генерируется БД) | `installments_payments` | `payment_id` | `BIGINT GENERATED ALWAYS AS IDENTITY` | 1 | Да | Да | Открытые |
| `installments_payments.csv` (`SK_ID_PREV`); для платежей по текущему договору `NULL` | `installments_payments` | `prev_application_id` | `INT (FK)` | 1054186 | Нет | Нет | Открытые |
| Синтетика (для платежей по текущему договору; иначе `NULL`) | `installments_payments` | `contract_id` | `INT (FK)` | 1 | Нет | Нет | Открытые |
| `installments_payments.csv` (`NUM_INSTALMENT_VERSION`); для синтетических платежей 1 | `installments_payments` | `instalment_version` | `SMALLINT` | 1 | Да | Нет | Коммерческая тайна |
| `installments_payments.csv` (`NUM_INSTALMENT_NUMBER`) | `installments_payments` | `instalment_number` | `SMALLINT` | 6 | Да | Нет | Коммерческая тайна |
| `installments_payments.csv` (`DAYS_INSTALMENT`), пересчёт в дату; для договоров от `issue_date` | `installments_payments` | `due_date` | `DATE` | 2022-04-10 | Да | Нет | Коммерческая тайна |
| `installments_payments.csv` (`DAYS_ENTRY_PAYMENT`), пересчёт в дату | `installments_payments` | `payment_date` | `DATE` | 2022-04-03 | Нет | Нет | Коммерческая тайна |
| `installments_payments.csv` (`AMT_INSTALMENT`) | `installments_payments` | `amt_instalment` | `NUMERIC(12,2)` | 6948.36 | Да | Нет | Коммерческая тайна |
| `installments_payments.csv` (`AMT_PAYMENT`) | `installments_payments` | `amt_payment` | `NUMERIC(12,2)` | 6948.36 | Нет | Нет | Коммерческая тайна |

Ограничение `chk_payment_one_parent`: заполнено ровно одно из полей `prev_application_id` и `contract_id`. Платежи по прошлым кредитам берутся из датасета, по текущим договорам генерируются синтетически.

## 13. `audit_log`

| Источник данных | Сущность | Атрибут | Тип данных | Пример значения | Обязательность | Уникальность | Примечание |
|---|---|---|---|---|---|---|---|
| Служебное (генерируется БД) (триггер) | `audit_log` | `audit_id` | `BIGINT GENERATED ALWAYS AS IDENTITY` | 1 | Да | Да | Открытые |
| Служебное (триггер) | `audit_log` | `table_name` | `VARCHAR(63)` | loan_contract | Да | Нет | Открытые |
| Служебное (триггер) | `audit_log` | `operation` | `VARCHAR(6)` | UPDATE | Да | Нет | Открытые |
| Служебное (триггер) | `audit_log` | `record_pk` | `TEXT` | 1 | Нет | Нет | Открытые |
| Служебное (`current_user`) | `audit_log` | `db_user` | `VARCHAR(63)` | admin_user | Да | Нет | Открытые |
| Служебное (`now()`) | `audit_log` | `changed_at` | `TIMESTAMPTZ` | 2026-03-20 14:05:33+03 | Да | Нет | Открытые |
| Служебное (триггер) | `audit_log` | `old_data` | `JSONB` | {"status_ref_id": 61} | Нет | Нет | Может содержать ПДн и коммерческую тайну (копия строки) |
| Служебное (триггер) | `audit_log` | `new_data` | `JSONB` | {"status_ref_id": 62} | Нет | Нет | Может содержать ПДн и коммерческую тайну (копия строки) |

---

## Итог по категориям

| Категория | Где |
|---|---|
| **ПДн** | `client_personal` (все поля, кроме ключа), `guarantor` (ФИО, `passport_no`, `phone`, `relation_ref_id`) |
| **Коммерческая тайна** | `client_financials`, `loan_contract`, `collateral`, суммы, дата заявки, скоринг и `target` в `application`, `previous_application`, `bureau`, `installments_payments` (платежи и по прошлым кредитам, и по текущим договорам) |
| **Открытые** | справочник `ref_dictionary`, идентификаторы, характеристики жилья, служебные поля |
| **Косвенные идентификаторы** | `gender`, `birth_year`, `cnt_children`, `education_ref_id`, `family_status_ref_id`, `occupation_ref_id` в `client`; `cnt_fam_members` в `application`; тип жилья, материал стен и тип дома в `application_housing` |
| **Смешанные** | `audit_log.old_data` и `new_data` (копии строк любых таблиц, доступ ограничивать как к ПДн) |
