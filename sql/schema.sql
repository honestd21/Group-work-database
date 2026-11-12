-- =====================================================================
-- schema.sql: DDL базы данных потребительского кредитования (Home Credit)
-- СУБД: PostgreSQL 14+ (проверено на 16)
-- 13 таблиц, 5 групп: клиент, заявка и договор, кредитная история,
-- платежи, служебные.
--
-- Источники: docs/analysis/tables_overview.md (типы, ограничения, индексы),
--            docs/analysis/data_map.md (источники полей),
--            docs/analysis/data_classification.md (категории данных).
--
-- Пометка «синт.» в комментариях: в датасете поля нет, значение генерируется
-- (docs/synthetic_data.md).
--
-- Все объекты создаются в схеме public. Права на таблицы выдаются в roles.sql,
-- триггеры и функции находятся в triggers_functions.sql.
--
-- Запуск: psql -U <user> -d <db> -f sql/schema.sql
-- =====================================================================

-- Пересоздание с нуля (раскомментировать при повторном запуске на пустой
-- учебной базе; удалит все данные).
-- DROP TABLE IF EXISTS installments_payments, guarantor, collateral,
--     loan_contract, application_housing, application, previous_application,
--     bureau, client_financials, client_personal, client, audit_log,
--     ref_dictionary CASCADE;

BEGIN;

-- =====================================================================
-- 1. СЛУЖЕБНЫЕ ТАБЛИЦЫ
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1.1. ref_dictionary: единый справочник категориальных значений
-- Категории: client_type, education, family_status, income_type,
-- occupation, contract_type, housing_type, walls_material, house_type,
-- loan_status, collateral_type, guarantor_relation, credit_active,
-- credit_type, prev_contract_status, reject_reason, goods_category.
-- Допущение: внешний ключ проверяет только существование ref_id, но не
-- принадлежность к нужной категории (см. tables_overview.md, п. 2.13).
-- ---------------------------------------------------------------------
CREATE TABLE ref_dictionary (
    ref_id       INT GENERATED ALWAYS AS IDENTITY,
    category     VARCHAR(40)  NOT NULL,
    code         VARCHAR(80)  NOT NULL,
    description  VARCHAR(200),
    CONSTRAINT pk_ref_dictionary          PRIMARY KEY (ref_id),
    CONSTRAINT uq_ref_dictionary_cat_code UNIQUE (category, code)
);

-- ---------------------------------------------------------------------
-- 1.2. audit_log: журнал аудита (заполняется триггерами)
-- Связей с другими таблицами нет намеренно: журнал должен сохраняться,
-- даже если запись в основной таблице удалена.
-- Содержит копии строк таблиц с ПДн и коммерческой тайной.
-- ---------------------------------------------------------------------
CREATE TABLE audit_log (
    audit_id    BIGINT GENERATED ALWAYS AS IDENTITY,
    table_name  VARCHAR(63)  NOT NULL,
    operation   VARCHAR(6)   NOT NULL,
    record_pk   TEXT,
    db_user     VARCHAR(63)  NOT NULL DEFAULT current_user,
    changed_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    old_data    JSONB,
    new_data    JSONB,
    CONSTRAINT pk_audit_log PRIMARY KEY (audit_id),
    CONSTRAINT chk_audit_operation
        CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    CONSTRAINT chk_audit_has_data
        CHECK (old_data IS NOT NULL OR new_data IS NOT NULL)
);

-- =====================================================================
-- 2. КЛИЕНТ
-- =====================================================================

-- ---------------------------------------------------------------------
-- 2.1. client: заёмщик (обезличенные демографические признаки)
-- В датасете нет идентификатора клиента (SK_ID_CURR идентифицирует заявку),
-- поэтому клиент выделен в отдельную таблицу с собственным ключом.
-- ---------------------------------------------------------------------
CREATE TABLE client (
    client_id            INT GENERATED ALWAYS AS IDENTITY,       -- синт.
    client_type_ref_id   INT      NOT NULL,                      -- физлицо / ИП; синт.
    gender               CHAR(1)  NOT NULL,                      -- CODE_GENDER (XNA исключено)
    birth_year           SMALLINT NOT NULL,                      -- из DAYS_BIRTH; полная дата не хранится
    education_ref_id     INT      NOT NULL,                      -- NAME_EDUCATION_TYPE
    family_status_ref_id INT      NOT NULL,                      -- NAME_FAMILY_STATUS
    income_type_ref_id   INT      NOT NULL,                      -- NAME_INCOME_TYPE
    occupation_ref_id    INT,                                    -- OCCUPATION_TYPE; много пропусков
    cnt_children         SMALLINT NOT NULL,                      -- CNT_CHILDREN
    own_car              BOOLEAN  NOT NULL,                      -- FLAG_OWN_CAR
    own_realty           BOOLEAN  NOT NULL,                      -- FLAG_OWN_REALTY
    created_at           DATE     NOT NULL DEFAULT current_date, -- синт.
    CONSTRAINT pk_client PRIMARY KEY (client_id),
    CONSTRAINT fk_client_type
        FOREIGN KEY (client_type_ref_id)   REFERENCES ref_dictionary (ref_id),
    CONSTRAINT fk_client_education
        FOREIGN KEY (education_ref_id)     REFERENCES ref_dictionary (ref_id),
    CONSTRAINT fk_client_family_status
        FOREIGN KEY (family_status_ref_id) REFERENCES ref_dictionary (ref_id),
    CONSTRAINT fk_client_income_type
        FOREIGN KEY (income_type_ref_id)   REFERENCES ref_dictionary (ref_id),
    CONSTRAINT fk_client_occupation
        FOREIGN KEY (occupation_ref_id)    REFERENCES ref_dictionary (ref_id),
    CONSTRAINT chk_client_gender       CHECK (gender IN ('M', 'F')),
    CONSTRAINT chk_client_birth_year   CHECK (birth_year BETWEEN 1920 AND 2008),
    CONSTRAINT chk_client_cnt_children CHECK (cnt_children >= 0)
);

-- ---------------------------------------------------------------------
-- 2.2. client_personal: персональные данные заёмщика (152-ФЗ)
-- Вынесена отдельно, чтобы права на таблицу выдавались отдельно
-- (аналитик доступа не имеет). Все значения синт. (Faker, ru_RU).
-- ---------------------------------------------------------------------
CREATE TABLE client_personal (
    client_id             INT          NOT NULL,
    last_name             VARCHAR(60)  NOT NULL,
    first_name            VARCHAR(60)  NOT NULL,
    middle_name           VARCHAR(60),                           -- отчество может отсутствовать
    passport_no           CHAR(10)     NOT NULL,                 -- серия и номер
    phone                 VARCHAR(16)  NOT NULL,
    email                 VARCHAR(254),
    registration_address  TEXT         NOT NULL,
    CONSTRAINT pk_client_personal PRIMARY KEY (client_id),
    CONSTRAINT fk_client_personal_client
        FOREIGN KEY (client_id) REFERENCES client (client_id) ON DELETE CASCADE,
    CONSTRAINT uq_client_personal_passport UNIQUE (passport_no),
    CONSTRAINT uq_client_personal_email    UNIQUE (email),
    CONSTRAINT chk_client_personal_passport CHECK (passport_no ~ '^[0-9]{10}$'),
    CONSTRAINT chk_client_personal_phone    CHECK (phone ~ '^\+7[0-9]{10}$')
);

-- ---------------------------------------------------------------------
-- 2.3. client_financials: выручка и чистая прибыль по годам (синт.)
-- Коммерческая тайна. На ней строятся проверка «кредит не больше 50 %
-- выручки», расчёт уровня риска и ТОП заёмщиков по прибыли.
-- ---------------------------------------------------------------------
CREATE TABLE client_financials (
    client_id    INT           NOT NULL,
    fiscal_year  SMALLINT      NOT NULL,
    revenue      NUMERIC(14,2) NOT NULL,                         -- от AMT_INCOME_TOTAL, не меньше 2 x loan_amount
    net_profit   NUMERIC(14,2) NOT NULL,                         -- может быть отрицательной
    CONSTRAINT pk_client_financials PRIMARY KEY (client_id, fiscal_year),
    CONSTRAINT fk_client_financials_client
        FOREIGN KEY (client_id) REFERENCES client (client_id) ON DELETE CASCADE,
    CONSTRAINT chk_fin_fiscal_year CHECK (fiscal_year BETWEEN 2000 AND 2100),
    CONSTRAINT chk_fin_revenue     CHECK (revenue >= 0),
    CONSTRAINT chk_fin_net_profit  CHECK (net_profit <= revenue)
);

-- =====================================================================
-- 3. ЗАЯВКА И ДОГОВОР
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3.1. application: текущая заявка (одна строка = одна строка
-- application_train.csv)
-- ---------------------------------------------------------------------
CREATE TABLE application (
    application_id              INT           NOT NULL,          -- SK_ID_CURR
    client_id                   INT           NOT NULL,          -- синт.
    contract_type_ref_id        INT           NOT NULL,          -- NAME_CONTRACT_TYPE (Cash / Revolving)
    application_date            DATE          NOT NULL,          -- синт., от опорной даты
    amt_income_total            NUMERIC(14,2) NOT NULL,          -- AMT_INCOME_TOTAL
    amt_credit                  NUMERIC(14,2) NOT NULL,          -- AMT_CREDIT
    amt_annuity                 NUMERIC(12,2),                   -- AMT_ANNUITY; есть пропуски
    amt_goods_price             NUMERIC(14,2),                   -- AMT_GOODS_PRICE; есть пропуски
    cnt_fam_members             SMALLINT,                        -- CNT_FAM_MEMBERS
    region_rating               SMALLINT      NOT NULL,          -- REGION_RATING_CLIENT
    region_population_relative  NUMERIC(9,6),                    -- REGION_POPULATION_RELATIVE
    ext_source_1                NUMERIC(10,9),                   -- внешний скоринговый балл
    ext_source_2                NUMERIC(10,9),
    ext_source_3                NUMERIC(10,9),
    bureau_enquiries_cnt        SMALLINT,                        -- AMT_REQ_CREDIT_BUREAU_YEAR
    target                      SMALLINT      NOT NULL,          -- 1 = проблемы с платежами
    CONSTRAINT pk_application PRIMARY KEY (application_id),
    CONSTRAINT fk_application_client
        FOREIGN KEY (client_id) REFERENCES client (client_id),
    CONSTRAINT fk_application_contract_type
        FOREIGN KEY (contract_type_ref_id) REFERENCES ref_dictionary (ref_id),
    CONSTRAINT chk_app_income        CHECK (amt_income_total > 0),
    CONSTRAINT chk_app_credit        CHECK (amt_credit > 0),
    CONSTRAINT chk_app_annuity       CHECK (amt_annuity > 0),
    CONSTRAINT chk_app_goods_price   CHECK (amt_goods_price > 0),
    CONSTRAINT chk_app_fam_members   CHECK (cnt_fam_members >= 1),
    CONSTRAINT chk_app_region_rating CHECK (region_rating IN (1, 2, 3)),
    CONSTRAINT chk_app_region_pop    CHECK (region_population_relative BETWEEN 0 AND 1),
    CONSTRAINT chk_app_ext_source_1  CHECK (ext_source_1 BETWEEN 0 AND 1),
    CONSTRAINT chk_app_ext_source_2  CHECK (ext_source_2 BETWEEN 0 AND 1),
    CONSTRAINT chk_app_ext_source_3  CHECK (ext_source_3 BETWEEN 0 AND 1),
    CONSTRAINT chk_app_bureau_enq    CHECK (bureau_enquiries_cnt >= 0),
    CONSTRAINT chk_app_target        CHECK (target IN (0, 1))
);

-- ---------------------------------------------------------------------
-- 3.2. application_housing: характеристики жилья по заявке
-- Оставлено около 10 из 47 исходных столбцов, одна версия показателей
-- (AVG / MODE), нормированные значения 0–1.
-- ---------------------------------------------------------------------
CREATE TABLE application_housing (
    application_id         INT NOT NULL,
    housing_type_ref_id    INT,                                  -- NAME_HOUSING_TYPE
    walls_material_ref_id  INT,                                  -- WALLSMATERIAL_MODE
    house_type_ref_id      INT,                                  -- HOUSETYPE_MODE
    apartments_avg         NUMERIC(6,4),                         -- APARTMENTS_AVG
    living_area_avg        NUMERIC(6,4),                         -- LIVINGAREA_AVG
    total_area_mode        NUMERIC(6,4),                         -- TOTALAREA_MODE
    floors_max_avg         NUMERIC(6,4),                         -- FLOORSMAX_AVG
    elevators_avg          NUMERIC(6,4),                         -- ELEVATORS_AVG
    years_build_avg        NUMERIC(6,4),                         -- YEARS_BUILD_AVG
    emergency_state        BOOLEAN,                              -- EMERGENCYSTATE_MODE (Yes/No)
    CONSTRAINT pk_application_housing PRIMARY KEY (application_id),
    CONSTRAINT fk_housing_application
        FOREIGN KEY (application_id) REFERENCES application (application_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_housing_type
        FOREIGN KEY (housing_type_ref_id)   REFERENCES ref_dictionary (ref_id),
    CONSTRAINT fk_housing_walls
        FOREIGN KEY (walls_material_ref_id) REFERENCES ref_dictionary (ref_id),
    CONSTRAINT fk_housing_house_type
        FOREIGN KEY (house_type_ref_id)     REFERENCES ref_dictionary (ref_id),
    CONSTRAINT chk_housing_apartments CHECK (apartments_avg  BETWEEN 0 AND 1),
    CONSTRAINT chk_housing_living     CHECK (living_area_avg BETWEEN 0 AND 1),
    CONSTRAINT chk_housing_total      CHECK (total_area_mode BETWEEN 0 AND 1),
    CONSTRAINT chk_housing_floors     CHECK (floors_max_avg  BETWEEN 0 AND 1),
    CONSTRAINT chk_housing_elevators  CHECK (elevators_avg   BETWEEN 0 AND 1),
    CONSTRAINT chk_housing_years      CHECK (years_build_avg BETWEEN 0 AND 1)
);

-- ---------------------------------------------------------------------
-- 3.3. loan_contract: кредитный договор (синт.)
-- Каждая заявка из application_train — выданный кредит, поэтому договор
-- создаётся для каждой заявки (связь 1 : 0..1, UNIQUE по application_id).
-- ---------------------------------------------------------------------
CREATE TABLE loan_contract (
    contract_id         INT GENERATED ALWAYS AS IDENTITY,
    application_id      INT           NOT NULL,
    contract_number     VARCHAR(20)   NOT NULL,                  -- бизнес-идентификатор, напр. LC-2026-000001
    issue_date          DATE          NOT NULL,                  -- после даты заявки
    loan_amount         NUMERIC(14,2) NOT NULL,                  -- копия application.amt_credit
    interest_rate       NUMERIC(5,2)  NOT NULL,                  -- % годовых
    term_months         SMALLINT      NOT NULL,                  -- из AMT_CREDIT / AMT_ANNUITY
    outstanding_amount  NUMERIC(14,2) NOT NULL,                  -- должно согласовываться с платежами
    status_ref_id       INT           NOT NULL,                  -- действует / закрыт / просрочен
    CONSTRAINT pk_loan_contract PRIMARY KEY (contract_id),
    CONSTRAINT fk_contract_application
        FOREIGN KEY (application_id) REFERENCES application (application_id),
    CONSTRAINT fk_contract_status
        FOREIGN KEY (status_ref_id)  REFERENCES ref_dictionary (ref_id),
    CONSTRAINT uq_contract_application UNIQUE (application_id),
    CONSTRAINT uq_contract_number      UNIQUE (contract_number),
    CONSTRAINT chk_contract_amount     CHECK (loan_amount > 0),
    CONSTRAINT chk_contract_rate       CHECK (interest_rate BETWEEN 0 AND 100),
    CONSTRAINT chk_contract_term       CHECK (term_months > 0),
    CONSTRAINT chk_contract_outstanding
        CHECK (outstanding_amount >= 0 AND outstanding_amount <= loan_amount)
);

-- ---------------------------------------------------------------------
-- 3.4. collateral: обеспечение (залог) по договору (синт.)
-- Для проверки «стоимость обеспечения меньше 80 % суммы кредита».
-- ---------------------------------------------------------------------
CREATE TABLE collateral (
    collateral_id           INT GENERATED ALWAYS AS IDENTITY,
    contract_id             INT           NOT NULL,
    collateral_type_ref_id  INT           NOT NULL,              -- недвижимость, автомобиль, депозит и др.
    appraised_value         NUMERIC(14,2) NOT NULL,              -- формула от AMT_GOODS_PRICE
    appraisal_date          DATE          NOT NULL,
    CONSTRAINT pk_collateral PRIMARY KEY (collateral_id),
    CONSTRAINT fk_collateral_contract
        FOREIGN KEY (contract_id) REFERENCES loan_contract (contract_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_collateral_type
        FOREIGN KEY (collateral_type_ref_id) REFERENCES ref_dictionary (ref_id),
    CONSTRAINT chk_collateral_value CHECK (appraised_value > 0)
);

-- ---------------------------------------------------------------------
-- 3.5. guarantor: поручитель по договору (синт.)
-- ПДн третьего лица, закрыта от аналитика так же, как client_personal.
-- ---------------------------------------------------------------------
CREATE TABLE guarantor (
    guarantor_id     INT GENERATED ALWAYS AS IDENTITY,
    contract_id      INT          NOT NULL,
    last_name        VARCHAR(60)  NOT NULL,
    first_name       VARCHAR(60)  NOT NULL,
    middle_name      VARCHAR(60),
    passport_no      CHAR(10)     NOT NULL,
    phone            VARCHAR(16)  NOT NULL,
    relation_ref_id  INT          NOT NULL,                      -- родственник, друг, коллега
    CONSTRAINT pk_guarantor PRIMARY KEY (guarantor_id),
    CONSTRAINT fk_guarantor_contract
        FOREIGN KEY (contract_id) REFERENCES loan_contract (contract_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_guarantor_relation
        FOREIGN KEY (relation_ref_id) REFERENCES ref_dictionary (ref_id),
    CONSTRAINT uq_guarantor_contract_passport UNIQUE (contract_id, passport_no),
    CONSTRAINT chk_guarantor_passport CHECK (passport_no ~ '^[0-9]{10}$'),
    CONSTRAINT chk_guarantor_phone    CHECK (phone ~ '^\+7[0-9]{10}$')
);

-- =====================================================================
-- 4. КРЕДИТНАЯ ИСТОРИЯ
-- =====================================================================

-- ---------------------------------------------------------------------
-- 4.1. previous_application: прошлые заявки клиента в Home Credit
-- Здесь встречаются Consumer loans и отказы.
-- ---------------------------------------------------------------------
CREATE TABLE previous_application (
    prev_application_id    INT           NOT NULL,               -- SK_ID_PREV
    client_id              INT           NOT NULL,               -- SK_ID_CURR -> заявка -> клиент
    contract_type_ref_id   INT           NOT NULL,               -- Cash / Consumer / Revolving
    status_ref_id          INT           NOT NULL,               -- NAME_CONTRACT_STATUS
    reject_reason_ref_id   INT,                                  -- CODE_REJECT_REASON; только для отказов
    goods_category_ref_id  INT,                                  -- NAME_GOODS_CATEGORY
    decision_date          DATE          NOT NULL,               -- из DAYS_DECISION
    amt_application        NUMERIC(14,2),                        -- AMT_APPLICATION
    amt_credit             NUMERIC(14,2),                        -- AMT_CREDIT
    amt_annuity            NUMERIC(12,2),                        -- AMT_ANNUITY
    cnt_payment            SMALLINT,                             -- плановое число платежей
    CONSTRAINT pk_previous_application PRIMARY KEY (prev_application_id),
    CONSTRAINT fk_prev_client
        FOREIGN KEY (client_id) REFERENCES client (client_id),
    CONSTRAINT fk_prev_contract_type
        FOREIGN KEY (contract_type_ref_id)  REFERENCES ref_dictionary (ref_id),
    CONSTRAINT fk_prev_status
        FOREIGN KEY (status_ref_id)         REFERENCES ref_dictionary (ref_id),
    CONSTRAINT fk_prev_reject_reason
        FOREIGN KEY (reject_reason_ref_id)  REFERENCES ref_dictionary (ref_id),
    CONSTRAINT fk_prev_goods_category
        FOREIGN KEY (goods_category_ref_id) REFERENCES ref_dictionary (ref_id),
    CONSTRAINT chk_prev_amt_application CHECK (amt_application >= 0),
    CONSTRAINT chk_prev_amt_credit      CHECK (amt_credit >= 0),
    CONSTRAINT chk_prev_amt_annuity     CHECK (amt_annuity >= 0),
    CONSTRAINT chk_prev_cnt_payment     CHECK (cnt_payment > 0)
);

-- ---------------------------------------------------------------------
-- 4.2. bureau: кредиты клиента в других организациях (кредитное бюро)
-- ---------------------------------------------------------------------
CREATE TABLE bureau (
    bureau_id               INT           NOT NULL,              -- SK_ID_BUREAU
    client_id               INT           NOT NULL,              -- SK_ID_CURR -> заявка -> клиент
    credit_active_ref_id    INT           NOT NULL,              -- CREDIT_ACTIVE
    credit_type_ref_id      INT           NOT NULL,              -- CREDIT_TYPE
    date_open               DATE          NOT NULL,              -- из DAYS_CREDIT
    date_end_planned        DATE,                                -- из DAYS_CREDIT_ENDDATE; есть пропуски
    amt_credit_sum          NUMERIC(14,2),                       -- AMT_CREDIT_SUM
    amt_credit_sum_debt     NUMERIC(14,2),                       -- AMT_CREDIT_SUM_DEBT
    amt_credit_sum_overdue  NUMERIC(14,2),                       -- AMT_CREDIT_SUM_OVERDUE
    credit_day_overdue      INT           NOT NULL,              -- CREDIT_DAY_OVERDUE
    cnt_credit_prolong      SMALLINT      NOT NULL,              -- CNT_CREDIT_PROLONG
    CONSTRAINT pk_bureau PRIMARY KEY (bureau_id),
    CONSTRAINT fk_bureau_client
        FOREIGN KEY (client_id) REFERENCES client (client_id),
    CONSTRAINT fk_bureau_credit_active
        FOREIGN KEY (credit_active_ref_id) REFERENCES ref_dictionary (ref_id),
    CONSTRAINT fk_bureau_credit_type
        FOREIGN KEY (credit_type_ref_id)   REFERENCES ref_dictionary (ref_id),
    CONSTRAINT chk_bureau_sum          CHECK (amt_credit_sum >= 0),
    CONSTRAINT chk_bureau_sum_debt     CHECK (amt_credit_sum_debt >= 0),
    CONSTRAINT chk_bureau_sum_overdue  CHECK (amt_credit_sum_overdue >= 0),
    CONSTRAINT chk_bureau_day_overdue  CHECK (credit_day_overdue >= 0),
    CONSTRAINT chk_bureau_prolong      CHECK (cnt_credit_prolong >= 0)
);

-- =====================================================================
-- 5. ПЛАТЕЖИ
-- =====================================================================

-- ---------------------------------------------------------------------
-- 5.1. installments_payments: платежи по прошлым кредитам (датасет,
-- prev_application_id) и по текущим договорам (синт., contract_id).
-- Платёж относится ровно к одному кредиту (exclusive arc): одна таблица
-- платежей вместо двух одинаковых.
-- ---------------------------------------------------------------------
CREATE TABLE installments_payments (
    payment_id           BIGINT GENERATED ALWAYS AS IDENTITY,
    prev_application_id  INT,                                    -- SK_ID_PREV; для текущих договоров NULL
    contract_id          INT,                                    -- для прошлых кредитов NULL
    instalment_version   SMALLINT      NOT NULL,                 -- NUM_INSTALMENT_VERSION; для синт. всегда 1
    instalment_number    SMALLINT      NOT NULL,                 -- NUM_INSTALMENT_NUMBER
    due_date             DATE          NOT NULL,                 -- из DAYS_INSTALMENT; для договоров от issue_date
    payment_date         DATE,                                   -- из DAYS_ENTRY_PAYMENT; NULL, если не внесён
    amt_instalment       NUMERIC(12,2) NOT NULL,                 -- AMT_INSTALMENT
    amt_payment          NUMERIC(12,2),                          -- AMT_PAYMENT; NULL, если не внесён
    CONSTRAINT pk_installments_payments PRIMARY KEY (payment_id),
    CONSTRAINT fk_payment_prev_application
        FOREIGN KEY (prev_application_id) REFERENCES previous_application (prev_application_id),
    CONSTRAINT fk_payment_contract
        FOREIGN KEY (contract_id) REFERENCES loan_contract (contract_id)
        ON DELETE CASCADE,
    CONSTRAINT chk_payment_one_parent
        CHECK (num_nonnulls(prev_application_id, contract_id) = 1),
    CONSTRAINT chk_payment_number         CHECK (instalment_number > 0),
    CONSTRAINT chk_payment_amt_instalment CHECK (amt_instalment >= 0),
    CONSTRAINT chk_payment_amt_payment    CHECK (amt_payment >= 0)
);

-- =====================================================================
-- 6. ИНДЕКСЫ
-- PostgreSQL сам создаёт индексы для PRIMARY KEY и UNIQUE, но не для
-- внешних ключей, поэтому нужные индексы по столбцам-ссылкам создаются
-- явно. Столбцы *_ref_id в справочник не индексируются: значений мало,
-- планировщик всё равно выберет последовательное чтение.
-- =====================================================================

-- Заявки клиента, соединение application с client
CREATE INDEX idx_application_client_id
    ON application (client_id);

-- ТОП заёмщиков по чистой прибыли за год
CREATE INDEX idx_client_fin_year_profit
    ON client_financials (fiscal_year, net_profit DESC);

-- Суммирование обеспечения по договору
CREATE INDEX idx_collateral_contract_id
    ON collateral (contract_id);

-- Выборка договоров по статусу и периоду
CREATE INDEX idx_loan_contract_status
    ON loan_contract (status_ref_id, issue_date);

-- История обращений клиента
CREATE INDEX idx_prev_application_client_id
    ON previous_application (client_id);

-- Кредиты клиента в бюро
CREATE INDEX idx_bureau_client_id
    ON bureau (client_id);

-- Платежи по прошлому кредиту в порядке номеров
CREATE INDEX idx_installments_prev_app
    ON installments_payments (prev_application_id, instalment_number);

-- Платежи по текущему договору в порядке номеров; просрочки.
-- Частичный индекс: строки с NULL (прошлые кредиты) в него не попадают.
CREATE INDEX idx_installments_contract
    ON installments_payments (contract_id, instalment_number)
    WHERE contract_id IS NOT NULL;

-- Журнал дописывается по времени, данные физически упорядочены:
-- BRIN занимает килобайты
CREATE INDEX idx_audit_changed_brin
    ON audit_log USING BRIN (changed_at);

-- Поиск по содержимому JSON в снимках строк
CREATE INDEX idx_audit_new_data_gin
    ON audit_log USING GIN (new_data jsonb_path_ops);

-- =====================================================================
-- 7. КОММЕНТАРИИ К ТАБЛИЦАМ С ЗАЩИЩАЕМЫМИ ДАННЫМИ
-- Категории по docs/analysis/data_classification.md
-- =====================================================================
COMMENT ON TABLE client_personal    IS 'ПДн (152-ФЗ): ФИО, паспорт, телефон, e-mail, адрес. Доступ только у уполномоченных ролей';
COMMENT ON TABLE guarantor          IS 'ПДн третьего лица (152-ФЗ): ФИО, паспорт, телефон, родство поручителя';
COMMENT ON TABLE client             IS 'Обезличенные признаки клиента; gender, birth_year, образование, семейное положение, профессия, число детей — косвенные идентификаторы; income_type, own_car, own_realty — коммерческая тайна';
COMMENT ON TABLE client_financials  IS 'Коммерческая тайна: выручка и чистая прибыль';
COMMENT ON TABLE loan_contract      IS 'Коммерческая тайна: условия договора, ставка, остаток долга';
COMMENT ON TABLE collateral         IS 'Коммерческая тайна: имущество в залоге и его оценка';
COMMENT ON TABLE application         IS 'Коммерческая тайна: дата заявки, суммы, внешние скоринговые баллы, число запросов в бюро, target; cnt_fam_members — косвенный идентификатор';
COMMENT ON TABLE application_housing  IS 'Нормированные характеристики жилья (открытые); housing_type, walls_material, house_type — косвенные идентификаторы';
COMMENT ON TABLE previous_application IS 'Коммерческая тайна: статусы и причины отказов, даты решений, суммы прошлых заявок';
COMMENT ON TABLE bureau               IS 'Коммерческая тайна: кредитная история клиента в других организациях (218-ФЗ)';
COMMENT ON TABLE installments_payments IS 'Коммерческая тайна: графики и факт платежей по прошлым кредитам и текущим договорам';
COMMENT ON TABLE audit_log          IS 'Журнал аудита; old_data/new_data содержат копии строк с ПДн и коммерческой тайной, доступ только администратору БД и службе безопасности';

COMMIT;
