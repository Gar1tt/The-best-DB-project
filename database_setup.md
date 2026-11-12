# Hospital Database: Setup Documentation

Part of the project **Authentication and Access Control of a Hospital Database** (MariaDB).
This document covers the database structure and the generated test data.

> All data in this database is **fake** (generated with Mockaroo). No real patient data is used.

## 1. Environment

| Item | Value |
|---|---|
| DBMS | MariaDB 13.1.1 |
| Client | HeidiSQL 12.20 |
| Database name | `hospital` |
| Test data generator | [Mockaroo](https://www.mockaroo.com) |

## 2. Tables

| Table | Description | Rows |
|---|---|---|
| `departments` | One hospital department (e.g. Cardiology) | 8 |
| `roles` | One job role (Doctor, Nurse, Receptionist, Admin) | 4 |
| `permissions` | One specific action that can be allowed (e.g. `read_medical_record`) | 8 |
| `role_permissions` | One permission granted to one role | 20 |
| `staff` | One hospital employee | 30 |
| `accounts` | One login account belonging to one staff member | 30 |
| `patients` | One registered patient | 200 |
| `appointments` | One scheduled visit between a patient and a staff member | 500 |
| `medical_records` | One entry written about a patient by a staff member | 500 |
| `audit_log` | One recorded action (login, view, edit) by an account | 1000 |

### Relationships (foreign keys)

- `staff.role_id` → `roles.role_id`
- `staff.dept_id` → `departments.dept_id`
- `accounts.staff_id` → `staff.staff_id` (one account per staff member)
- `role_permissions.role_id` → `roles.role_id`
- `role_permissions.permission_id` → `permissions.permission_id`
- `appointments.patient_id` → `patients.patient_id`
- `appointments.staff_id` → `staff.staff_id`
- `medical_records.patient_id` → `patients.patient_id`
- `medical_records.staff_id` → `staff.staff_id`
- `audit_log.account_id` → `accounts.account_id`

## 3. Schema

```sql
CREATE DATABASE hospital;
USE hospital;

CREATE TABLE departments (
  dept_id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL
);

CREATE TABLE roles (
  role_id INT AUTO_INCREMENT PRIMARY KEY,
  role_name VARCHAR(50) NOT NULL
);

CREATE TABLE permissions (
  permission_id INT AUTO_INCREMENT PRIMARY KEY,
  permission_name VARCHAR(100) NOT NULL
);

CREATE TABLE role_permissions (
  role_id INT, permission_id INT,
  PRIMARY KEY (role_id, permission_id),
  FOREIGN KEY (role_id) REFERENCES roles(role_id),
  FOREIGN KEY (permission_id) REFERENCES permissions(permission_id)
);

CREATE TABLE staff (
  staff_id INT AUTO_INCREMENT PRIMARY KEY,
  first_name VARCHAR(50), last_name VARCHAR(50),
  role_id INT, dept_id INT,
  email VARCHAR(100), hire_date DATE,
  FOREIGN KEY (role_id) REFERENCES roles(role_id),
  FOREIGN KEY (dept_id) REFERENCES departments(dept_id)
);

CREATE TABLE accounts (
  account_id INT AUTO_INCREMENT PRIMARY KEY,
  staff_id INT UNIQUE, username VARCHAR(50) UNIQUE,
  password_hash VARCHAR(255), is_active BOOLEAN, last_login DATETIME,
  FOREIGN KEY (staff_id) REFERENCES staff(staff_id)
);

CREATE TABLE patients (
  patient_id INT AUTO_INCREMENT PRIMARY KEY,
  first_name VARCHAR(50), last_name VARCHAR(50),
  birth_date DATE, gender VARCHAR(20),
  phone VARCHAR(30), address VARCHAR(200), insurance_no VARCHAR(30)
);

CREATE TABLE appointments (
  appointment_id INT AUTO_INCREMENT PRIMARY KEY,
  patient_id INT, staff_id INT, appointment_date DATETIME, status VARCHAR(20),
  FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
  FOREIGN KEY (staff_id) REFERENCES staff(staff_id)
);

CREATE TABLE medical_records (
  record_id INT AUTO_INCREMENT PRIMARY KEY,
  patient_id INT, staff_id INT,
  diagnosis VARCHAR(255), notes TEXT, record_date DATE,
  FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
  FOREIGN KEY (staff_id) REFERENCES staff(staff_id)
);

CREATE TABLE audit_log (
  log_id INT AUTO_INCREMENT PRIMARY KEY,
  account_id INT, action VARCHAR(30),
  action_time DATETIME, ip_address VARCHAR(45),
  FOREIGN KEY (account_id) REFERENCES accounts(account_id)
);
```

## 4. Test data

### 4.1 Hand-written tables (access control definition)

These tables define the access control model, so they were written by hand instead of generated randomly.

```sql
INSERT INTO departments (name) VALUES
('Cardiology'),('Neurology'),('Emergency'),('Pediatrics'),
('Radiology'),('Oncology'),('Orthopedics'),('Administration');

INSERT INTO roles (role_name) VALUES
('Doctor'),('Nurse'),('Receptionist'),('Admin');

INSERT INTO permissions (permission_name) VALUES
('read_patient'),          -- 1
('write_patient'),         -- 2
('read_medical_record'),   -- 3
('write_medical_record'),  -- 4
('read_appointment'),      -- 5
('write_appointment'),     -- 6
('read_audit_log'),        -- 7
('manage_accounts');       -- 8

-- roles: 1 Doctor, 2 Nurse, 3 Receptionist, 4 Admin
INSERT INTO role_permissions (role_id, permission_id) VALUES
(1,1),(1,3),(1,4),(1,5),
(2,1),(2,3),(2,5),(2,6),
(3,1),(3,2),(3,5),(3,6),
(4,1),(4,2),(4,3),(4,4),(4,5),(4,6),(4,7),(4,8);
```

### 4.2 Role / permission matrix

| Permission | Doctor | Nurse | Receptionist | Admin |
|---|:-:|:-:|:-:|:-:|
| read_patient | ✓ | ✓ | ✓ | ✓ |
| write_patient | | | ✓ | ✓ |
| read_medical_record | ✓ | ✓ | | ✓ |
| write_medical_record | ✓ | | | ✓ |
| read_appointment | ✓ | ✓ | ✓ | ✓ |
| write_appointment | | ✓ | ✓ | ✓ |
| read_audit_log | | | | ✓ |
| manage_accounts | | | | ✓ |

### 4.3 Generated tables (Mockaroo)

Each table was generated in Mockaroo with **Format: SQL**, the matching table name, and "include CREATE TABLE" unticked.

| Table | Rows | Key field settings |
|---|---|---|
| `staff` | 30 | `role_id` Number 1-4, `dept_id` Number 1-8, `hire_date` Date |
| `accounts` | 30 | `staff_id` Row Number (one account per staff), `password_hash` SHA-256, `is_active` Boolean |
| `patients` | 200 | `birth_date` Date 1930-2020, `insurance_no` regex `[A-Z]{2}[0-9]{8}` |
| `appointments` | 500 | `patient_id` 1-200, `staff_id` 1-30, `status` Custom List (Scheduled, Completed, Cancelled) |
| `medical_records` | 500 | `patient_id` 1-200, `staff_id` 1-30, `diagnosis` Custom List |
| `audit_log` | 1000 | `account_id` 1-30, `action` Custom List (LOGIN, LOGOUT, VIEW_RECORD, EDIT_RECORD, FAILED_LOGIN), `ip_address` IP v4 |

Foreign key columns use number ranges that match the row counts of the parent tables, so every reference points to an existing row.

### 4.4 Load order

Because of foreign keys, data must be loaded in this order:

1. `departments`, `roles`, `permissions`, `role_permissions`
2. `staff`
3. `accounts`
4. `patients`
5. `appointments`, `medical_records`, `audit_log`

## 5. Problems encountered and fixes

| Problem | Cause | Fix |
|---|---|---|
| Mockaroo dates rejected by MariaDB (`8/19/2026`) | MariaDB expects `YYYY-MM-DD` | Set the Mockaroo date format to `%Y-%m-%d` (datetimes: `%Y-%m-%d %H:%M:%S`), or use Find/Replace with regex `'(\d{1,2})/(\d{1,2})/(\d{4})'` → `'$3-$1-$2'` |
| `Can't create database 'hospital'; database exists` | Script was run a second time | Do not re-run `CREATE` scripts; check with `SHOW TABLES;` |
| Duplicate rows in `departments` and `roles` (48 and 24) | INSERT script was executed 6 times (F9 runs the whole tab) | `SET FOREIGN_KEY_CHECKS = 0; TRUNCATE TABLE ...; SET FOREIGN_KEY_CHECKS = 1;` then insert again |
| Missing tables (`role_permissions`, `medical_records`, `audit_log`) | Schema script stopped partway | Created the missing tables separately |
| `staff` count stayed 0 | Inserts had not succeeded because of the date format and missing `USE hospital;` | Fixed dates, added `USE hospital;` as line 1, ran once |
| HeidiSQL export: `Unable to create directory` | Filename had no folder path | Chose a full path with the folder button |

## 6. Verification queries

```sql
USE hospital;
SELECT COUNT(*) FROM departments;      -- 8
SELECT COUNT(*) FROM roles;            -- 4
SELECT COUNT(*) FROM permissions;      -- 8
SELECT COUNT(*) FROM role_permissions; -- 20
SELECT COUNT(*) FROM staff;            -- 30
SELECT COUNT(*) FROM accounts;         -- 30
SELECT COUNT(*) FROM patients;         -- 200
SELECT COUNT(*) FROM appointments;     -- 500
SELECT COUNT(*) FROM medical_records;  -- 500
SELECT COUNT(*) FROM audit_log;        -- 1000
```

## 7. Restoring the database

The file `hospital_full.sql` (exported from HeidiSQL: right-click `hospital` → *Export database as SQL*, with Create for database and tables, Data = Insert) contains the full schema and data.

1. If a `hospital` database already exists, run `DROP DATABASE hospital;` first.
2. Open `hospital_full.sql` in HeidiSQL (or run `mariadb -u root -p < hospital_full.sql`).
3. Execute it **once**.
4. Run the verification queries above.

## 8. Notes for the access control part

- MariaDB has **no `DENY` statement**. Access is denied by not granting a privilege, and `REVOKE` removes a granted privilege. Restricted access is shown with column-level grants and views.
- The `roles` / `permissions` / `role_permissions` tables are an application-level model of access. The actual enforcement uses MariaDB `CREATE ROLE`, `GRANT`, and `CREATE USER`.
- Passwords used for test users are demo values only. Do not commit real credentials.
