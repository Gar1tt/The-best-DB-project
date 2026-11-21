-- ============================================================
-- Hospital database: roles, views, users and privileges (MariaDB)
--
-- HOW TO RUN: connected as root, load hospital_full.sql first,
-- then run this file ONCE (F9 in HeidiSQL).
-- The script can be re-run safely: it drops the old users,
-- roles and views first, then rebuilds everything.
--
-- Demo passwords only. Never use real passwords in the repository.
-- ============================================================

USE hospital;

-- ------------------------------------------------------------
-- 0. Clean start (users first, then roles, then views)
-- ------------------------------------------------------------
DROP USER IF EXISTS 'dr_test'@'localhost';
DROP USER IF EXISTS 'nurse_test'@'localhost';
DROP USER IF EXISTS 'reception_test'@'localhost';
DROP USER IF EXISTS 'admin_test'@'localhost';

DROP ROLE IF EXISTS doctor;
DROP ROLE IF EXISTS nurse;
DROP ROLE IF EXISTS receptionist;
DROP ROLE IF EXISTS hospital_admin;

DROP VIEW IF EXISTS staff_directory;
DROP VIEW IF EXISTS patient_contact;

-- ------------------------------------------------------------
-- 1. Views (expose only the safe columns)
--    A view runs with the privileges of its creator (root), so
--    users of the view need no rights on the underlying table.
-- ------------------------------------------------------------
CREATE VIEW staff_directory AS
  SELECT staff_id, first_name, last_name, role_id, dept_id
  FROM staff;                                   -- hides email and hire_date

CREATE VIEW patient_contact AS
  SELECT patient_id, first_name, last_name, birth_date, gender, phone, address
  FROM patients;                                -- hides insurance_no

-- ------------------------------------------------------------
-- 2. Create the roles
-- ------------------------------------------------------------
CREATE ROLE doctor;
CREATE ROLE nurse;
CREATE ROLE receptionist;
CREATE ROLE hospital_admin;

-- ------------------------------------------------------------
-- 3. DOCTOR
--    read patients, read/write medical records, read appointments
-- ------------------------------------------------------------
GRANT SELECT ON hospital.patients TO doctor;
GRANT SELECT, INSERT, UPDATE ON hospital.medical_records TO doctor;
GRANT SELECT ON hospital.appointments TO doctor;

-- ------------------------------------------------------------
-- 4. NURSE
--    read patients, read medical records, read/write appointments
-- ------------------------------------------------------------
GRANT SELECT ON hospital.patients TO nurse;
GRANT SELECT ON hospital.medical_records TO nurse;
GRANT SELECT, INSERT, UPDATE ON hospital.appointments TO nurse;

-- ------------------------------------------------------------
-- 5. RECEPTIONIST
--    read/write patient contact data through the view
--    (insurance_no is not in the view), read/write appointments,
--    NO access to the patients table or to medical records
-- ------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON hospital.patient_contact TO receptionist;
GRANT SELECT, INSERT, UPDATE ON hospital.appointments TO receptionist;

-- ------------------------------------------------------------
-- 6. Shared read access for doctor, nurse and receptionist:
--    lookup tables and the staff directory view.
--    The staff table itself, accounts and audit_log stay hidden.
-- ------------------------------------------------------------
GRANT SELECT ON hospital.departments TO doctor, nurse, receptionist;
GRANT SELECT ON hospital.roles TO doctor, nurse, receptionist;
GRANT SELECT ON hospital.staff_directory TO doctor, nurse, receptionist;

-- ------------------------------------------------------------
-- 7. ADMIN: everything in the hospital database
-- ------------------------------------------------------------
GRANT ALL PRIVILEGES ON hospital.* TO hospital_admin;

-- ------------------------------------------------------------
-- 8. Test users (one per role) and role assignment
-- ------------------------------------------------------------
CREATE USER 'dr_test'@'localhost'        IDENTIFIED BY 'Doctor!Test1';
CREATE USER 'nurse_test'@'localhost'     IDENTIFIED BY 'Nurse!Test1';
CREATE USER 'reception_test'@'localhost' IDENTIFIED BY 'Reception!Test1';
CREATE USER 'admin_test'@'localhost'     IDENTIFIED BY 'Admin!Test1';

GRANT doctor         TO 'dr_test'@'localhost';
GRANT nurse          TO 'nurse_test'@'localhost';
GRANT receptionist   TO 'reception_test'@'localhost';
GRANT hospital_admin TO 'admin_test'@'localhost';

-- Activate the role automatically at login
SET DEFAULT ROLE doctor         FOR 'dr_test'@'localhost';
SET DEFAULT ROLE nurse          FOR 'nurse_test'@'localhost';
SET DEFAULT ROLE receptionist   FOR 'reception_test'@'localhost';
SET DEFAULT ROLE hospital_admin FOR 'admin_test'@'localhost';

-- ------------------------------------------------------------
-- 9. Show the result (take screenshots for the report)
-- ------------------------------------------------------------
SHOW GRANTS FOR doctor;
SHOW GRANTS FOR nurse;
SHOW GRANTS FOR receptionist;
SHOW GRANTS FOR hospital_admin;
SHOW GRANTS FOR 'reception_test'@'localhost';

-- ------------------------------------------------------------
-- 10. REVOKE demo (optional, run these two lines separately)
-- ------------------------------------------------------------
-- REVOKE UPDATE ON hospital.medical_records FROM doctor;
-- GRANT  UPDATE ON hospital.medical_records TO doctor;   -- restore
