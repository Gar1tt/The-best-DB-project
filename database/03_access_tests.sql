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
-- Sections A to D test the normal permissions of each role.
-- Sections F to H are attacks against the DENY rules.
-- Sections I and J show what the DENY rules do NOT protect.
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
--    The DENY lines are listed next to the GRANT lines.
-- ------------------------------------------------------------
-- SHOW GRANTS FOR hospital_staff;
-- SHOW GRANTS FOR doctor;
-- SHOW GRANTS FOR nurse;
-- SHOW GRANTS FOR receptionist;
-- SHOW GRANTS FOR hospital_admin;

-- ------------------------------------------------------------
-- F. Attack: try to GRANT a denied table back
--    A DENY beats every GRANT. Run F1 as root, F2 as dr_test,
--    F3 as root again to clean up.
-- ------------------------------------------------------------
-- F1 (root): four attempts to give the doctor the accounts table
GRANT SELECT ON hospital.accounts TO doctor;                  -- to the job role
GRANT SELECT ON hospital.accounts TO hospital_staff;          -- to the base role
GRANT SELECT ON hospital.accounts TO 'dr_test'@'localhost', 'dr_test'@'%';   -- to the user
GRANT SELECT ON *.* TO 'dr_test'@'localhost', 'dr_test'@'%';  -- on every database
FLUSH PRIVILEGES;

-- F2 (dr_test, new session): DENIED (1142) although all four grants exist
SELECT * FROM accounts;

-- F3 (root): remove the test grants again
REVOKE SELECT ON hospital.accounts FROM doctor;
REVOKE SELECT ON hospital.accounts FROM hospital_staff;
REVOKE SELECT ON hospital.accounts FROM 'dr_test'@'localhost', 'dr_test'@'%';
REVOKE SELECT ON *.* FROM 'dr_test'@'localhost', 'dr_test'@'%';
FLUSH PRIVILEGES;

-- ------------------------------------------------------------
-- G. Attack: a restricted user tries to lift the restriction
--    Run as dr_test. All DENIED.
-- ------------------------------------------------------------
SET ROLE hospital_admin;                                      -- 1959: role was never granted
GRANT SELECT ON hospital.accounts TO doctor;                  -- 1142: no GRANT OPTION
REVOKE DENY ALL PRIVILEGES ON hospital.accounts FROM hospital_staff;   -- 1142
SHOW GRANTS FOR hospital_staff;                               -- 1044: cannot read the mysql database

-- ------------------------------------------------------------
-- H. Attack: the admin tries to tamper with the audit log
--    Run as admin_test.
-- ------------------------------------------------------------
-- ALLOWED
SELECT COUNT(*) FROM audit_log;

-- DENIED (1142, except DROP DATABASE: 1044)
UPDATE audit_log SET action = 'LOGIN' WHERE log_id = 1;
DELETE FROM audit_log WHERE log_id = 1;
TRUNCATE TABLE audit_log;
DROP TABLE audit_log;
ALTER TABLE audit_log ADD COLUMN x INT;
RENAME TABLE audit_log TO audit_log_old;
CREATE TRIGGER trg BEFORE INSERT ON audit_log FOR EACH ROW SET NEW.action = 'HIDDEN';
DROP DATABASE hospital;
REVOKE DENY UPDATE ON hospital.audit_log FROM hospital_admin;

-- ------------------------------------------------------------
-- I. Known gap: a new table is open by default
--    The base role has SELECT on hospital.*, so every new table
--    is readable until it is denied. I1 and I3 as root, I2 as dr_test.
-- ------------------------------------------------------------
-- I1 (root)
CREATE TABLE hospital.salaries (staff_id INT, amount INT);
INSERT INTO hospital.salaries VALUES (1, 5000);

-- I2 (dr_test): ALLOWED, although nobody decided the doctor may read it
SELECT * FROM salaries;

-- I3 (root): clean up
DROP TABLE hospital.salaries;

-- ------------------------------------------------------------
-- J. Known gap (seen on MariaDB 13.1.1 and 13.1.2): a deny can be skipped until
--    the privileges are reloaded.
--    Same idea as F, but WITHOUT the FLUSH PRIVILEGES. The deny on
--    accounts is inherited by doctor from hospital_staff. A table
--    grant to doctor plus a global grant to the user gets past it
--    until FLUSH PRIVILEGES is run. J1, J3, J5 as root, J2, J4 as dr_test.
-- ------------------------------------------------------------
-- J1 (root)
GRANT SELECT ON hospital.accounts TO doctor;
GRANT SELECT ON *.* TO 'dr_test'@'localhost', 'dr_test'@'%';

-- J2 (dr_test, new session): ALLOWED. This is the gap.
SELECT * FROM accounts;

-- J3 (root)
FLUSH PRIVILEGES;

-- J4 (dr_test, new session): DENIED (1142)
SELECT * FROM accounts;

-- J5 (root): clean up
REVOKE SELECT ON hospital.accounts FROM doctor;
REVOKE SELECT ON *.* FROM 'dr_test'@'localhost', 'dr_test'@'%';
FLUSH PRIVILEGES;
