-- Fresh demo database only. Import hospital_full.sql first. This file creates
-- roles, views and a live audit log, not login accounts. The bootstrap creates
-- the four ED25519 logins and assigns their roles after TLS is configured.
USE hospital;

CREATE USER 'hospital_view_owner'@'localhost' ACCOUNT LOCK;
GRANT SELECT (patient_id, first_name, last_name, birth_date, gender, phone, address),
      UPDATE (phone) ON hospital.patients TO 'hospital_view_owner'@'localhost';
GRANT SELECT (staff_id, first_name, last_name, role_id, dept_id)
    ON hospital.staff TO 'hospital_view_owner'@'localhost';
GRANT SELECT (account_id, staff_id, username, is_active, last_login)
    ON hospital.accounts TO 'hospital_view_owner'@'localhost';

CREATE OR REPLACE DEFINER='hospital_view_owner'@'localhost' SQL SECURITY DEFINER
VIEW patient_contact AS
    SELECT patient_id, first_name, last_name, birth_date, gender, phone, address FROM patients;
CREATE OR REPLACE DEFINER='hospital_view_owner'@'localhost' SQL SECURITY DEFINER
VIEW staff_directory AS
    SELECT staff_id, first_name, last_name, role_id, dept_id FROM staff;
CREATE DEFINER='hospital_view_owner'@'localhost' SQL SECURITY DEFINER
VIEW staff_login_directory AS
    SELECT account_id, staff_id, username, is_active, last_login FROM accounts;

CREATE ROLE hospital_staff;
CREATE ROLE doctor;
CREATE ROLE nurse;
CREATE ROLE receptionist;
CREATE ROLE hospital_admin;

-- Explicit shared objects; adding a table does not make it readable.
GRANT SELECT ON hospital.appointments TO hospital_staff;
GRANT SELECT ON hospital.patient_contact TO hospital_staff;
GRANT SELECT ON hospital.staff_directory TO hospital_staff;
GRANT SELECT ON hospital.departments TO hospital_staff;
GRANT SELECT ON hospital.roles TO hospital_staff;
DENY ALL PRIVILEGES ON hospital.accounts TO hospital_staff;
DENY ALL PRIVILEGES ON hospital.staff TO hospital_staff;
DENY ALL PRIVILEGES ON hospital.audit_log TO hospital_staff;

GRANT hospital_staff TO doctor;
GRANT SELECT ON hospital.patients TO doctor;
GRANT SELECT ON hospital.medical_records TO doctor;
GRANT INSERT (patient_id, staff_id, diagnosis, notes, record_date)
    ON hospital.medical_records TO doctor;

GRANT hospital_staff TO nurse;
GRANT INSERT (patient_id, staff_id, appointment_date, status)
    ON hospital.appointments TO nurse;
-- This DENY overrides the read privilege inherited on patient_contact.
DENY SELECT (birth_date, gender, address) ON hospital.patient_contact TO nurse;
DENY ALL PRIVILEGES ON hospital.patients TO nurse;
DENY ALL PRIVILEGES ON hospital.medical_records TO nurse;

GRANT hospital_staff TO receptionist;
GRANT INSERT (patient_id, staff_id, appointment_date, status)
    ON hospital.appointments TO receptionist;
GRANT UPDATE (phone) ON hospital.patient_contact TO receptionist;
DENY ALL PRIVILEGES ON hospital.patients TO receptionist;
DENY ALL PRIVILEGES ON hospital.medical_records TO receptionist;

-- The app's admin role is an operations reviewer, not MariaDB root.
GRANT SELECT ON hospital.audit_log TO hospital_admin;
GRANT SELECT ON hospital.staff_login_directory TO hospital_admin;
GRANT SELECT ON hospital.staff_directory TO hospital_admin;
GRANT SELECT ON hospital.departments TO hospital_admin;
GRANT SELECT ON hospital.roles TO hospital_admin;
DENY ALL PRIVILEGES ON hospital.accounts TO hospital_admin;
DENY INSERT, UPDATE, DELETE, DROP, ALTER, TRIGGER ON hospital.audit_log TO hospital_admin;

CREATE DATABASE hospital_audit;
CREATE TABLE hospital_audit.events (
    event_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    occurred_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    actor VARCHAR(384) NOT NULL,
    action_name VARCHAR(32) NOT NULL,
    object_id INT NOT NULL
) ENGINE=InnoDB;

GRANT SELECT ON hospital_audit.events TO hospital_admin;
DENY INSERT, UPDATE, DELETE, DROP, ALTER, TRIGGER ON hospital_audit.events TO hospital_admin;
DENY ALL PRIVILEGES ON hospital_audit.events TO hospital_staff;

-- A locked definer can append only through these triggers. USER() records
-- the connected login; CURRENT_USER() here would instead name the definer.
CREATE USER 'hospital_audit_writer'@'localhost' ACCOUNT LOCK;
GRANT INSERT ON hospital_audit.events TO 'hospital_audit_writer'@'localhost';
GRANT TRIGGER, SELECT ON hospital.medical_records TO 'hospital_audit_writer'@'localhost';
GRANT TRIGGER, SELECT ON hospital.appointments TO 'hospital_audit_writer'@'localhost';
GRANT TRIGGER, SELECT ON hospital.patients TO 'hospital_audit_writer'@'localhost';

CREATE DEFINER='hospital_audit_writer'@'localhost' TRIGGER audit_diagnosis_added
AFTER INSERT ON hospital.medical_records FOR EACH ROW
    INSERT INTO hospital_audit.events (actor, action_name, object_id)
        VALUES (USER(), 'DIAGNOSIS_ADDED', NEW.record_id);

CREATE DEFINER='hospital_audit_writer'@'localhost' TRIGGER audit_appointment_booked
AFTER INSERT ON hospital.appointments FOR EACH ROW
    INSERT INTO hospital_audit.events (actor, action_name, object_id)
        VALUES (USER(), 'APPOINTMENT_BOOKED', NEW.appointment_id);

CREATE DEFINER='hospital_audit_writer'@'localhost' TRIGGER audit_patient_phone_changed
AFTER UPDATE ON hospital.patients FOR EACH ROW
    INSERT INTO hospital_audit.events (actor, action_name, object_id)
        SELECT USER(), 'PATIENT_PHONE_CHANGED', NEW.patient_id
        WHERE NOT (OLD.phone <=> NEW.phone);

FLUSH PRIVILEGES;
