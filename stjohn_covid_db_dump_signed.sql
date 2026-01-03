--COVID-19 HOSPITAL ANALYTICS (PostgreSQL)

CREATE DATABASE stjohns_covid_hospital;
\connect stjohns_covid_hospital;

-- ==========================================
BEGIN;

------------------------------
--Drop objects (so script reruns)
------------------------------
DROP VIEW IF EXISTS vw_exec_summary CASCADE;
DROP VIEW IF EXISTS vw_positivity_trend CASCADE;
DROP VIEW IF EXISTS vw_admissions_icu_trend CASCADE;
DROP VIEW IF EXISTS vw_capacity_pressure CASCADE;
DROP VIEW IF EXISTS vw_staffing_pressure CASCADE;

DROP TABLE IF EXISTS fact_staffing_daily CASCADE;
DROP TABLE IF EXISTS fact_capacity_daily CASCADE;
DROP TABLE IF EXISTS fact_covid_daily CASCADE;
DROP TABLE IF EXISTS dim_hospital_unit CASCADE;
DROP TABLE IF EXISTS dim_date CASCADE;

------------------------------
--Dimensions
------------------------------
CREATE TABLE dim_date (
  d DATE PRIMARY KEY,
  year INT NOT NULL,
  month INT NOT NULL,
  day INT NOT NULL,
  week INT NOT NULL
);

CREATE TABLE dim_hospital_unit (
  unit_id SERIAL PRIMARY KEY,
  unit_name TEXT NOT NULL UNIQUE CHECK (unit_name IN ('ED','Med','ICU'))
);

------------------------------
--Facts (daily)
------------------------------
CREATE TABLE fact_covid_daily (
  d DATE NOT NULL REFERENCES dim_date(d),
  unit_id INT NOT NULL REFERENCES dim_hospital_unit(unit_id),

  tests INT NOT NULL,
  positive_tests INT NOT NULL,

  covid_admissions INT NOT NULL,
  covid_discharges INT NOT NULL,

  icu_admissions INT NOT NULL,
  ventilated_patients INT NOT NULL,

  deaths INT NOT NULL,

  avg_los_days NUMERIC(4,2) NOT NULL,

  PRIMARY KEY (d, unit_id),
  CHECK (positive_tests <= tests)
);

CREATE TABLE fact_capacity_daily (
  d DATE NOT NULL REFERENCES dim_date(d),
  unit_id INT NOT NULL REFERENCES dim_hospital_unit(unit_id),

  beds_available INT NOT NULL,
  beds_occupied INT NOT NULL,

  PRIMARY KEY (d, unit_id),
  CHECK (beds_occupied <= beds_available)
);

CREATE TABLE fact_staffing_daily (
  d DATE NOT NULL REFERENCES dim_date(d),
  unit_id INT NOT NULL REFERENCES dim_hospital_unit(unit_id),

  staff_scheduled INT NOT NULL,
  staff_available INT NOT NULL,
  sick_calls INT NOT NULL,

  PRIMARY KEY (d, unit_id),
  CHECK (staff_available <= staff_scheduled)
);

------------------------------
--Seed dimensions
------------------------------
INSERT INTO dim_hospital_unit (unit_name) VALUES ('ED'), ('Med'), ('ICU');

-- Daily calendar: 2020-03-01 to 2022-12-31
INSERT INTO dim_date (d, year, month, day, week)
SELECT
  gs::date AS d,
  EXTRACT(YEAR FROM gs)::int,
  EXTRACT(MONTH FROM gs)::int,
  EXTRACT(DAY FROM gs)::int,
  EXTRACT(WEEK FROM gs)::int
FROM generate_series('2020-03-01'::date, '2022-12-31'::date, interval '1 day') gs;

------------------------------
--Synthetic COVID operations data
------------------------------

WITH base AS (
  SELECT
    d.d,
    u.unit_id,
    u.unit_name,
    (
      1.0
      + 0.9 * sin(2 * pi() * (EXTRACT(DOY FROM d.d)::numeric / 365.0))
      + 0.6 * sin(2 * pi() * (EXTRACT(DOY FROM d.d)::numeric / 180.0))
      + random() * 0.6
    ) AS wave
  FROM dim_date d
  CROSS JOIN dim_hospital_unit u
),
metrics AS (
  SELECT
    d,
    unit_id,
    unit_name,

    CASE
      WHEN unit_name='ED'  THEN (220 + wave*180 + random()*120)::int
      WHEN unit_name='Med' THEN (90  + wave*60  + random()*40 )::int
      ELSE                      (30  + wave*20  + random()*15 )::int
    END AS tests,

    LEAST(0.35, GREATEST(0.02, 0.05 + wave*0.08 + random()*0.05)) AS pos_rate,

    CASE
      WHEN unit_name='ED'  THEN (6 + wave*10 + random()*6)::int
      WHEN unit_name='Med' THEN (4 + wave*8  + random()*4)::int
      ELSE                      (1 + wave*3  + random()*2)::int
    END AS admissions
  FROM base
),
final AS (
  SELECT
    d,
    unit_id,
    unit_name,
    tests,
    (tests * pos_rate)::int AS positive_tests,

    GREATEST(0, (admissions - (random()*3)::int)) AS covid_admissions,
    GREATEST(0, (admissions - (random()*4)::int)) AS covid_discharges,

    CASE
      WHEN unit_name='ICU' THEN admissions
      WHEN unit_name='Med' THEN GREATEST(0, (admissions * (0.15 + random()*0.10))::int)
      ELSE                      GREATEST(0, (admissions * (0.08 + random()*0.08))::int)
    END AS icu_admissions,

    CASE WHEN unit_name='ICU' THEN GREATEST(0, (admissions * (0.35 + random()*0.20))::int)
         ELSE 0
    END AS ventilated_patients,

    CASE
      WHEN unit_name='ICU' THEN GREATEST(0, (admissions * (0.06 + random()*0.05))::int)
      WHEN unit_name='Med' THEN GREATEST(0, (admissions * (0.02 + random()*0.03))::int)
      ELSE                      GREATEST(0, (admissions * (0.01 + random()*0.02))::int)
    END AS deaths,

    ROUND(
      CASE
        WHEN unit_name='ICU' THEN 8.0 + random()*6.0
        WHEN unit_name='Med' THEN 5.0 + random()*4.0
        ELSE 2.5 + random()*2.0
      END
    , 2) AS avg_los_days
  FROM metrics
)
INSERT INTO fact_covid_daily (
  d, unit_id, tests, positive_tests, covid_admissions, covid_discharges,
  icu_admissions, ventilated_patients, deaths, avg_los_days
)
SELECT
  d, unit_id, tests, positive_tests, covid_admissions, covid_discharges,
  icu_admissions, ventilated_patients, deaths, avg_los_days
FROM final;

-- Capacity: fixed bed availability by unit; occupancy reacts to admissions (proxy pressure)
WITH cap AS (
  SELECT
    cd.d,
    cd.unit_id,
    u.unit_name,
    CASE
      WHEN u.unit_name='ED'  THEN 45
      WHEN u.unit_name='Med' THEN 180
      ELSE 24
    END AS beds_available,
    cd.covid_admissions,
    cd.icu_admissions
  FROM fact_covid_daily cd
  JOIN dim_hospital_unit u ON u.unit_id=cd.unit_id
)
INSERT INTO fact_capacity_daily (d, unit_id, beds_available, beds_occupied)
SELECT
  d,
  unit_id,
  beds_available,
  LEAST(
    beds_available,
    GREATEST(
      0,
      CASE
        WHEN unit_name='ICU' THEN 10 + icu_admissions*2 + (random()*6)::int
        WHEN unit_name='Med' THEN 90 + covid_admissions*2 + (random()*18)::int
        ELSE 18 + covid_admissions + (random()*10)::int
      END
    )
  ) AS beds_occupied
FROM cap;

-- Staffing: scheduled vs available; sick calls increase as occupancy rises
WITH staff_base AS (
  SELECT
    c.d,
    c.unit_id,
    u.unit_name,
    c.beds_occupied,
    c.beds_available,
    (c.beds_occupied::numeric / NULLIF(c.beds_available,0)) AS occ_rate
  FROM fact_capacity_daily c
  JOIN dim_hospital_unit u ON u.unit_id=c.unit_id
),
s AS (
  SELECT
    d,
    unit_id,
    unit_name,
    occ_rate,
    CASE
      WHEN unit_name='ICU' THEN 28
      WHEN unit_name='Med' THEN 70
      ELSE 35
    END AS staff_scheduled
  FROM staff_base
)
INSERT INTO fact_staffing_daily (d, unit_id, staff_scheduled, staff_available, sick_calls)
SELECT
  d,
  unit_id,
  staff_scheduled,
  GREATEST(0, (staff_scheduled - (1 + (occ_rate*6) + random()*3)::int)) AS staff_available,
  GREATEST(0, (0 + (occ_rate*5) + random()*2)::int) AS sick_calls
FROM s;

------------------------------
--Views (dashboard ready)
------------------------------

CREATE VIEW vw_exec_summary AS
SELECT
  MIN(d) AS start_date,
  MAX(d) AS end_date,
  SUM(tests) AS total_tests,
  SUM(positive_tests) AS total_positive,
  ROUND(SUM(positive_tests)::numeric / NULLIF(SUM(tests),0), 4) AS positivity_rate,
  SUM(covid_admissions) AS total_admissions,
  SUM(icu_admissions) AS total_icu_admissions,
  SUM(ventilated_patients) AS total_ventilated_patients,
  SUM(deaths) AS total_deaths,
  ROUND(SUM(deaths)::numeric / NULLIF(SUM(covid_admissions),0), 4) AS mortality_rate_est
FROM fact_covid_daily;

CREATE VIEW vw_positivity_trend AS
SELECT
  d,
  SUM(tests) AS tests,
  SUM(positive_tests) AS positives,
  ROUND(SUM(positive_tests)::numeric / NULLIF(SUM(tests),0), 4) AS positivity_rate
FROM fact_covid_daily
GROUP BY d
ORDER BY d;

CREATE VIEW vw_admissions_icu_trend AS
SELECT
  d,
  SUM(covid_admissions) AS admissions,
  SUM(icu_admissions) AS icu_admissions,
  SUM(ventilated_patients) AS ventilated,
  ROUND(AVG(avg_los_days), 2) AS avg_los_days
FROM fact_covid_daily
GROUP BY d
ORDER BY d;

CREATE VIEW vw_capacity_pressure AS
SELECT
  c.d,
  u.unit_name,
  c.beds_available,
  c.beds_occupied,
  ROUND(c.beds_occupied::numeric / NULLIF(c.beds_available,0), 4) AS occupancy_rate
FROM fact_capacity_daily c
JOIN dim_hospital_unit u ON u.unit_id=c.unit_id
ORDER BY c.d, u.unit_name;

CREATE VIEW vw_staffing_pressure AS
SELECT
  s.d,
  u.unit_name,
  s.staff_scheduled,
  s.staff_available,
  (s.staff_scheduled - s.staff_available) AS staffing_gap,
  s.sick_calls
FROM fact_staffing_daily s
JOIN dim_hospital_unit u ON u.unit_id=s.unit_id
ORDER BY s.d, u.unit_name;

COMMIT;
