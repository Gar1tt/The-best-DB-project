-- ============================================================
-- Access control tests for the hospital database
--
-- HOW TO USE
--  1. Open a separate HeidiSQL session for each test user
--     (File > Session manager > New, host 127.0.0.1).
--  2. Never run a whole section at once: a DENIED query raises an
--     error and stops everything after it. Put ONE query in a
--     tab, press F9, take a screenshot, then replace it with the
--     next one.
--  3. A "DENIED" query that gets denied is a PASS.
--
-- Test users (demo passwords):
--   dr_test         Doctor!Test1
--   nurse_test      Nurse!Test1
--   reception_test  Reception!Test1
--   admin_test      Admin!Test1
--
-- Docker: connect to host 127.0.0.1, port 3306. CURRENT_USER() then shows
-- the '%' account (for example dr_test@%) instead of dr_test@localhost.
-- The privileges are identical for both accounts.
--
-- The tests change a few rows (notes, appointment status, a phone
-- number, one new appointment). It is test data, so this is fine.
-- ============================================================

-- ------------------------------------------------------------
-- 0. First query in EVERY session: who am I?
-- ------------------------------------------------------------
USE hospital;
SELECT CURRENT_USER(), CURRENT_ROLE();

-- ------------------------------------------------------------
-- A. dr_test (doctor)
-- ------------------------------------------------------------
-- ALLOWED
SELECT * FROM patients LIMIT 5;
SELECT * FROM medical_records LIMIT 5;
UPDATE medical_records SET notes = 'Updated by doctor' WHERE record_id = 1;
SELECT * FROM appointments LIMIT 5;
SELECT * FROM staff_directory;

-- DENIED
UPDATE appointments SET status = 'Cancelled' WHERE appointment_id = 1;
UPDATE patients SET phone = '000' WHERE patient_id = 1;
SELECT * FROM staff;
SELECT * FROM accounts;
SELECT * FROM audit_log;

-- ------------------------------------------------------------
-- B. nurse_test (nurse)
-- ------------------------------------------------------------
-- ALLOWED
SELECT * FROM patients LIMIT 5;
SELECT * FROM medical_records LIMIT 5;
SELECT * FROM appointments LIMIT 5;
UPDATE appointments SET status = 'Completed' WHERE appointment_id = 1;
SELECT * FROM staff_directory;

-- DENIED
UPDATE medical_records SET notes = 'x' WHERE record_id = 1;
INSERT INTO medical_records (patient_id, staff_id, diagnosis) VALUES (1, 1, 'Flu');
UPDATE patients SET phone = '000' WHERE patient_id = 1;
SELECT * FROM staff;
SELECT * FROM accounts;
SELECT * FROM audit_log;

-- ------------------------------------------------------------
-- C. reception_test (receptionist)
-- ------------------------------------------------------------
-- ALLOWED
SELECT * FROM patient_contact LIMIT 5;
UPDATE patient_contact SET phone = '555-0100' WHERE patient_id = 1;
INSERT INTO appointments (patient_id, staff_id, appointment_date, status)
  VALUES (1, 1, '2026-12-01 10:00:00', 'Scheduled');
SELECT * FROM appointments LIMIT 5;
SELECT * FROM staff_directory;

-- DENIED
SELECT * FROM patients LIMIT 5;                    -- table not granted
UPDATE patients SET phone = '000' WHERE patient_id = 1;
SELECT insurance_no FROM patient_contact;          -- fails: unknown column (hidden by the view)
SELECT * FROM medical_records;
SELECT * FROM staff;
SELECT * FROM accounts;

-- ------------------------------------------------------------
-- D. admin_test (hospital_admin): everything is ALLOWED
-- ------------------------------------------------------------
SELECT * FROM accounts LIMIT 5;
SELECT * FROM audit_log LIMIT 5;
SELECT * FROM medical_records LIMIT 5;
SELECT * FROM patients LIMIT 5;
SELECT * FROM staff LIMIT 5;
SELECT * FROM permissions;
SELECT * FROM role_permissions;
UPDATE accounts SET is_active = 0 WHERE account_id = 1;
UPDATE accounts SET is_active = 1 WHERE account_id = 1;   -- restore

-- ------------------------------------------------------------
-- E. As root: show what each role really has
-- ------------------------------------------------------------
-- SHOW GRANTS FOR doctor;
-- SHOW GRANTS FOR nurse;
-- SHOW GRANTS FOR receptionist;
-- SHOW GRANTS FOR hospital_admin;
