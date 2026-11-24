-- ============================================================
-- Hospital database: roles, views, users and privileges (MariaDB 13.1+)
--
-- ACCESS MODEL: "grant broadly, then DENY the exceptions".
--   * hospital_staff  gets SELECT on the whole schema, and is DENIED the
--                     sensitive tables.
--   * doctor, nurse and receptionist inherit hospital_staff and add the
--     few write privileges their job needs.
--   * hospital_admin  gets ALL PRIVILEGES on the schema, and is DENIED
--                     tampering with the audit log.
--
-- A DENY always beats a GRANT, in any order and through any role, and it
-- can only be removed with REVOKE DENY. DENY needs MariaDB 13.1 or newer.
--
-- HOW TO RUN: connected as root, load hospital_full.sql first,
-- then run this file ONCE (F9 in HeidiSQL).
-- The script can be re-run safely: it drops the old users,
-- roles and views first, then rebuilds everything.
--
-- Each test user is created for two hosts:
--   'localhost'  a local MariaDB, or a client running inside the container
--   '%'          a client on the host machine connecting to the Docker
--                container (the connection arrives from a Docker address,
--                not from localhost). The compose file only publishes the
--                port on 127.0.0.1, so it is still reachable from this
--                machine only.
--
-- Demo passwords only. Never use real passwords in the repository.
-- ============================================================

USE hospital;

-- ------------------------------------------------------------
-- 0. Clean start (users first, then roles, then views)
--    Dropping a role also removes its grants and its denies.
-- ------------------------------------------------------------
DROP USER IF EXISTS 'dr_test'@'localhost',        'dr_test'@'%';
DROP USER IF EXISTS 'nurse_test'@'localhost',     'nurse_test'@'%';
DROP USER IF EXISTS 'reception_test'@'localhost', 'reception_test'@'%';
DROP USER IF EXISTS 'admin_test'@'localhost',     'admin_test'@'%';

DROP ROLE IF EXISTS doctor;
DROP ROLE IF EXISTS nurse;
DROP ROLE IF EXISTS receptionist;
DROP ROLE IF EXISTS hospital_admin;
DROP ROLE IF EXISTS hospital_staff;

DROP VIEW IF EXISTS staff_directory;
DROP VIEW IF EXISTS patient_contact;

-- ------------------------------------------------------------
-- 1. Views (expose only the safe columns)
--    A view runs with the privileges of its creator (root), so
--    users of the view need no rights on the underlying table.
--    This is how a role that is DENIED a table can still read
--    the harmless columns of it.
-- ------------------------------------------------------------
CREATE VIEW staff_directory AS
  SELECT staff_id, first_name, last_name, role_id, dept_id
  FROM staff;                                   -- hides email and hire_date

CREATE VIEW patient_contact AS
  SELECT patient_id, first_name, last_name, birth_date, gender, phone, address
  FROM patients;                                -- hides insurance_no

-- ------------------------------------------------------------
-- 2. Create the roles
--    hospital_staff is the shared base role. It is never given
--    to a user directly, only to the three job roles.
-- ------------------------------------------------------------
CREATE ROLE hospital_staff;
CREATE ROLE doctor;
CREATE ROLE nurse;
CREATE ROLE receptionist;
CREATE ROLE hospital_admin;

-- ------------------------------------------------------------
-- 3. HOSPITAL_STAFF (base role): read everything in the schema
--    EXCEPT the four tables that only the admin may touch, and
--    the staff table (staff read the staff_directory view instead).
--
--    One broad GRANT plus five DENYs replaces the old list of
--    one GRANT per table per role.
-- ------------------------------------------------------------
GRANT SELECT ON hospital.* TO hospital_staff;

DENY ALL PRIVILEGES ON hospital.accounts         TO hospital_staff;
DENY ALL PRIVILEGES ON hospital.audit_log        TO hospital_staff;
DENY ALL PRIVILEGES ON hospital.permissions      TO hospital_staff;
DENY ALL PRIVILEGES ON hospital.role_permissions TO hospital_staff;
DENY ALL PRIVILEGES ON hospital.staff            TO hospital_staff;

-- ------------------------------------------------------------
-- 4. DOCTOR = hospital_staff + write medical records
-- ------------------------------------------------------------
GRANT hospital_staff TO doctor;
GRANT INSERT, UPDATE ON hospital.medical_records TO doctor;

-- ------------------------------------------------------------
-- 5. NURSE = hospital_staff + write appointments
-- ------------------------------------------------------------
GRANT hospital_staff TO nurse;
GRANT INSERT, UPDATE ON hospital.appointments TO nurse;

-- ------------------------------------------------------------
-- 6. RECEPTIONIST = hospital_staff + write appointments
--    + write patient contact data through the view,
--    and DENIED the patients table and the medical records.
--    (insurance_no is only in the patients table, not in the view.)
-- ------------------------------------------------------------
GRANT hospital_staff TO receptionist;
GRANT INSERT, UPDATE ON hospital.appointments    TO receptionist;
GRANT INSERT, UPDATE ON hospital.patient_contact TO receptionist;

DENY ALL PRIVILEGES ON hospital.patients        TO receptionist;
DENY ALL PRIVILEGES ON hospital.medical_records TO receptionist;

-- ------------------------------------------------------------
-- 7. ADMIN: everything in the hospital database,
--    EXCEPT changing or removing the audit log.
--    The admin can read the log and new entries can be added,
--    but existing entries cannot be edited, deleted or dropped.
-- ------------------------------------------------------------
GRANT ALL PRIVILEGES ON hospital.* TO hospital_admin;

DENY UPDATE, DELETE, DROP, ALTER, TRIGGER ON hospital.audit_log TO hospital_admin;

-- ------------------------------------------------------------
-- 8. Test users (one per role) and role assignment
-- ------------------------------------------------------------
CREATE USER 'dr_test'@'localhost'        IDENTIFIED BY 'Doctor!Test1',
            'dr_test'@'%'                IDENTIFIED BY 'Doctor!Test1';
CREATE USER 'nurse_test'@'localhost'     IDENTIFIED BY 'Nurse!Test1',
            'nurse_test'@'%'             IDENTIFIED BY 'Nurse!Test1';
CREATE USER 'reception_test'@'localhost' IDENTIFIED BY 'Reception!Test1',
            'reception_test'@'%'         IDENTIFIED BY 'Reception!Test1';
CREATE USER 'admin_test'@'localhost'     IDENTIFIED BY 'Admin!Test1',
            'admin_test'@'%'             IDENTIFIED BY 'Admin!Test1';

GRANT doctor         TO 'dr_test'@'localhost',        'dr_test'@'%';
GRANT nurse          TO 'nurse_test'@'localhost',     'nurse_test'@'%';
GRANT receptionist   TO 'reception_test'@'localhost', 'reception_test'@'%';
GRANT hospital_admin TO 'admin_test'@'localhost',     'admin_test'@'%';

-- Activate the role automatically at login
SET DEFAULT ROLE doctor         FOR 'dr_test'@'localhost';
SET DEFAULT ROLE doctor         FOR 'dr_test'@'%';
SET DEFAULT ROLE nurse          FOR 'nurse_test'@'localhost';
SET DEFAULT ROLE nurse          FOR 'nurse_test'@'%';
SET DEFAULT ROLE receptionist   FOR 'reception_test'@'localhost';
SET DEFAULT ROLE receptionist   FOR 'reception_test'@'%';
SET DEFAULT ROLE hospital_admin FOR 'admin_test'@'localhost';
SET DEFAULT ROLE hospital_admin FOR 'admin_test'@'%';

-- ------------------------------------------------------------
-- 8b. Reload the privilege tables
--     Makes the server rebuild every role from what is stored, so
--     all denies are applied to all roles that inherit them.
--     Run this again after ANY later GRANT, DENY or REVOKE DENY.
--     (Tested on MariaDB 13.1.1 and 13.1.2: a deny inherited through
--     a role is not always applied until the privileges are reloaded.
--     See section J of 03_access_tests.sql.)
-- ------------------------------------------------------------
FLUSH PRIVILEGES;

-- ------------------------------------------------------------
-- 9. Show the result (take screenshots for the report)
--    The DENY lines appear next to the GRANT lines. Only an
--    account that can read the mysql database (root) sees them.
-- ------------------------------------------------------------
SHOW GRANTS FOR hospital_staff;
SHOW GRANTS FOR doctor;
SHOW GRANTS FOR nurse;
SHOW GRANTS FOR receptionist;
SHOW GRANTS FOR hospital_admin;
SHOW GRANTS FOR 'reception_test'@'localhost';

-- ------------------------------------------------------------
-- 10. Removing a deny (optional, run these two lines separately)
--     A later GRANT does NOT cancel a DENY. Only REVOKE DENY does.
-- ------------------------------------------------------------
-- REVOKE DENY ALL PRIVILEGES ON hospital.medical_records FROM receptionist;
-- DENY        ALL PRIVILEGES ON hospital.medical_records TO receptionist;   -- restore
