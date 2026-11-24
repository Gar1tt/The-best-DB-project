# Hospital Database: Setup Documentation

Part of the project **Authentication and Access Control of a Hospital Database** (MariaDB).
This document covers the database structure, the generated test data, and the roles and privileges.

> All data in this database is **fake** (generated with Mockaroo). No real patient data is used.

## Repository files

| File | Purpose |
|---|---|
| `hospital_full.sql` | Full export of the database: schema, views and data |
| `database/02_roles_grants.sql` | Roles, views, test users, and the `GRANT` and `DENY` statements |
| `database/03_access_tests.sql` | Allowed and denied queries used to test each role (sections A to D), and attacks against the `DENY` rules (sections F to J) |
| `database/screenshots/` | Evidence of the test results for sections A to D |
| `security/` | ED25519 and TLS setup for the test users, with its own tests and `README.md` |
| `DATABASE_SETUP.md` | This document |

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

Each pair in `role_permissions` is `(role_id, permission_id)`, for example `(1,3)` means "Doctor may read medical records".

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

## 5. Access control implementation

MariaDB 13.1 added the [`DENY`](https://mariadb.com/docs/server/reference/sql-statements/account-management-sql-statements/deny) statement, and this project uses it. The model is "grant broadly, then deny the exceptions": a role gets `SELECT` on the whole `hospital` schema, and the tables it must not touch are denied by name. Three rules make this work:

- A deny always beats a grant, in any order.
- A deny on a role applies to every role and user that holds it.
- Only `REVOKE DENY` removes a deny. A later `GRANT` does not.

The project uses three techniques:

1. **Roles**: privileges are granted to roles, and roles are assigned to users. The base role `hospital_staff` holds what doctor, nurse and receptionist have in common, and those three roles inherit it.
2. **`DENY`**: the base role is denied the sensitive tables, the receptionist is also denied `patients` and `medical_records`, and the admin is denied changing the audit log. A denied table is refused with error 1142 and does not appear in `SHOW TABLES`.
3. **Views**: a view exposes only safe columns. A role that is denied a table can still read the view on it.

The `roles`, `permissions` and `role_permissions` tables describe the access model in the data. The actual enforcement is done by MariaDB with `CREATE ROLE`, `GRANT`, `DENY` and `CREATE USER` in `database/02_roles_grants.sql`.

An earlier version of this document said that MariaDB has no `DENY` statement. That was true before version 13.1, and the first version of the grants used one `GRANT` per table per role instead.

### 5.1 Views

| View | Based on | Columns shown | Hidden columns |
|---|---|---|---|
| `staff_directory` | `staff` | staff_id, first_name, last_name, role_id, dept_id | email, hire_date |
| `patient_contact` | `patients` | patient_id, first_name, last_name, birth_date, gender, phone, address | insurance_no |

A view runs with the privileges of its creator (root), so users of the view need no rights on the underlying table. This also holds when the role is denied the table, because the deny applies to the role and not to root. This makes the view definition the security boundary: it must list only safe columns.

### 5.2 Roles, grants and denies

What `database/02_roles_grants.sql` defines:

| Role | Granted | Denied |
|---|---|---|
| `hospital_staff` (base role, not given to users directly) | `SELECT` on `hospital.*` | All privileges on `accounts`, `audit_log`, `permissions`, `role_permissions` and `staff` |
| `doctor` | `hospital_staff`; `INSERT, UPDATE` on `medical_records` | Inherited from `hospital_staff` |
| `nurse` | `hospital_staff`; `INSERT, UPDATE` on `appointments` | Inherited from `hospital_staff` |
| `receptionist` | `hospital_staff`; `INSERT, UPDATE` on `appointments` and on the view `patient_contact` | Inherited from `hospital_staff`, plus all privileges on `patients` and `medical_records` |
| `hospital_admin` | `ALL PRIVILEGES` on `hospital.*` | `UPDATE, DELETE, DROP, ALTER, TRIGGER` on `audit_log` |

The resulting privileges per object:

| Object | doctor | nurse | receptionist | hospital_admin |
|---|---|---|---|---|
| `patients` | SELECT | SELECT | denied | ALL |
| `patient_contact` (view) | SELECT | SELECT | SELECT, INSERT, UPDATE | ALL |
| `medical_records` | SELECT, INSERT, UPDATE | SELECT | denied | ALL |
| `appointments` | SELECT | SELECT, INSERT, UPDATE | SELECT, INSERT, UPDATE | ALL |
| `staff` | denied | denied | denied | ALL |
| `staff_directory` (view) | SELECT | SELECT | SELECT | ALL |
| `departments`, `roles` | SELECT | SELECT | SELECT | ALL |
| `accounts` | denied | denied | denied | ALL |
| `audit_log` | denied | denied | denied | ALL except UPDATE, DELETE, DROP, ALTER, TRIGGER |
| `permissions`, `role_permissions` | denied | denied | denied | ALL |

Compared with the first version of the grants, two things changed: doctors and nurses can now also read `patient_contact` (a subset of the `patients` table, which they could already read), and the admin can no longer change, delete or drop the audit log.

As root, `SHOW GRANTS FOR receptionist;` lists the `DENY` lines next to the `GRANT` lines. The denies are only shown to an account that can read the `mysql` database, so the four test users do not see them in their own `SHOW GRANTS`.

The script ends with `FLUSH PRIVILEGES`. Run `FLUSH PRIVILEGES` again after any later `GRANT`, `DENY` or `REVOKE DENY` (see section 9).

### 5.3 Test users (demo passwords only)

| User | Password | Role |
|---|---|---|
| `dr_test`@localhost | `Doctor!Test1` | doctor |
| `nurse_test`@localhost | `Nurse!Test1` | nurse |
| `reception_test`@localhost | `Reception!Test1` | receptionist |
| `admin_test`@localhost | `Admin!Test1` | hospital_admin |

Each user exists for the hosts `localhost` and `%`, and has the role set as the default role, so it is active at login. These credentials are fake and for testing only. Do not use real passwords in the repository.

These are the passwords that `database/02_roles_grants.sql` sets. They are valid only until `security/setup-hospital-users.sh` is run. That script switches all four users to ED25519 authentication with new passwords and requires TLS for them; see `security/README.md`.

## 6. Testing

Each user was tested in a separate HeidiSQL session (host `127.0.0.1`). The queries are in `database/03_access_tests.sql`. A denied query that gets denied counts as a pass. Screenshots are in `database/screenshots/`.

The screenshots for 6.1 to 6.5 were taken with the first, `GRANT`-only version of the grants. After the change to `DENY`, all 41 queries of sections A to D were run again on MariaDB 13.1.1 with the `mariadb` command-line client. Each gave the same result and the same error code as in the tables below.

### 6.1 Doctor (`dr_test`)

Login check: `SELECT CURRENT_USER(), CURRENT_ROLE();` returned `dr_test@localhost` with role `doctor` (`doctor_01_login_check.png`).

| Query | Expected | Actual | Screenshot |
|---|---|---|---|
| `SELECT * FROM patients` | Allowed | Allowed (5 rows, 8 columns) | `doctor_02_allowed_queries.png` |
| `SELECT * FROM medical_records` | Allowed | Allowed (5 rows, 6 columns) | `doctor_02_allowed_queries.png` |
| `UPDATE medical_records ...` | Allowed | Allowed (1 row matched, 1 changed) | `doctor_02_allowed_queries.png` |
| `SELECT * FROM appointments` | Allowed | Allowed (5 rows, 5 columns) | `doctor_02_allowed_queries.png` |
| `SELECT * FROM staff_directory` | Allowed | Allowed (30 rows, 5 columns) | `doctor_08_select_staff_directory_allowed.png` |
| `UPDATE appointments ...` | Denied (1142) | Denied (1142) | `doctor_03_update_appointments_denied.png` |
| `UPDATE patients ...` | Denied (1142) | Denied (1142) | `doctor_04_update_patients_denied.png` |
| `SELECT * FROM staff` | Denied (1142) | Denied (1142) | `doctor_07_select_staff_denied.png` |
| `SELECT * FROM accounts` | Denied (1142) | Denied (1142) | `doctor_05_select_accounts_denied.png` |
| `SELECT * FROM audit_log` | Denied (1142) | Denied (1142) | `doctor_06_select_audit_log_denied.png` |

The four allowed queries on `patients`, `medical_records`, `appointments` and the `UPDATE` were run together, so one screenshot (`doctor_02_allowed_queries.png`) shows them: one result tab per query, and the log line `Rows matched: 1  Changed: 1` for the update.

### 6.2 Nurse (`nurse_test`)

Login check: `SELECT CURRENT_USER(), CURRENT_ROLE();` returned `nurse_test@localhost` with role `nurse` (`nurse_01_login_check.png`).

| Query | Expected | Actual | Screenshot |
|---|---|---|---|
| `SELECT * FROM patients` | Allowed | Allowed (5 rows, 8 columns) | `nurse_02_select_patients_allowed.png` |
| `SELECT * FROM medical_records` | Allowed | Allowed (5 rows, 6 columns) | `nurse_03_select_medical_records_allowed.png` |
| `SELECT * FROM appointments` | Allowed | Allowed (5 rows, 5 columns) | `nurse_04_select_appointments_allowed.png` |
| `UPDATE appointments ...` | Allowed | Allowed (ran without error; 1 row matched, 0 changed because the status was already `Completed`) | `nurse_05_update_appointments_allowed.png` |
| `SELECT * FROM staff_directory` | Allowed | Allowed (30 rows, 5 columns) | `nurse_06_select_staff_directory_allowed.png` |
| `UPDATE medical_records ...` | Denied (1142) | Denied (1142) | `nurse_07_update_medical_records_denied.png` |
| `INSERT INTO medical_records ...` | Denied (1142) | Denied (1142) | `nurse_08_insert_medical_records_denied.png` |
| `UPDATE patients ...` | Denied (1142) | Denied (1142) | `nurse_09_update_patients_denied.png` |
| `SELECT * FROM staff` | Denied (1142) | Denied (1142) | `nurse_10_select_staff_denied.png` |
| `SELECT * FROM accounts` | Denied (1142) | Denied (1142) | `nurse_11_select_accounts_denied.png` |
| `SELECT * FROM audit_log` | Denied (1142) | Denied (1142) | `nurse_12_select_audit_log_denied.png` |

### 6.3 Receptionist (`reception_test`)

Login check: `SELECT CURRENT_USER(), CURRENT_ROLE();` returned `reception_test@localhost` with role `receptionist` (`reception_01_login_check.png`).

| Query | Expected | Actual | Screenshot |
|---|---|---|---|
| `SELECT * FROM patient_contact` | Allowed | Allowed (5 rows, 7 columns, no `insurance_no`) | `reception_02_allowed_queries.png` |
| `UPDATE patient_contact ...` | Allowed | Allowed (1 row matched, 1 changed) | `reception_02_allowed_queries.png` |
| `INSERT INTO appointments ...` | Allowed | Allowed (1 row inserted; the log reports 2 affected rows in total, the update plus this insert) | `reception_02_allowed_queries.png` |
| `SELECT * FROM appointments` | Allowed | Allowed (5 rows, 5 columns) | `reception_03_select_appointments_allowed.png` |
| `SELECT * FROM staff_directory` | Allowed | Allowed (30 rows, 5 columns) | `reception_04_select_staff_directory_allowed.png` |
| `SELECT * FROM patients` | Denied (1142) | Denied (1142) | `reception_05_select_patients_denied.png` |
| `UPDATE patients ...` | Denied (1142) | Denied (1142) | `reception_06_update_patients_denied.png` |
| `SELECT insurance_no FROM patient_contact` | Error: unknown column (1054) | Error 1054, unknown column `insurance_no` | `reception_07_select_insurance_no_denied.png` |
| `SELECT * FROM medical_records` | Denied (1142) | Denied (1142) | `reception_08_select_medical_records_denied.png` |
| `SELECT * FROM staff` | Denied (1142) | Denied (1142) | `reception_09_select_staff_denied.png` |
| `SELECT * FROM accounts` | Denied (1142) | Denied (1142) | `reception_10_select_accounts_denied.png` |

The three allowed queries on `patient_contact` and `appointments` were run together, so one screenshot shows them. The update through the view reached the base table: the admin's `patients` result (`admin_05_select_patients_allowed.png`) shows the phone number `555-0100` for patient 1.

### 6.4 Admin (`admin_test`)

Login check: `SELECT CURRENT_USER(), CURRENT_ROLE();` returned `admin_test@localhost` with role `hospital_admin` (`admin_01_login_check.png`).

| Query | Expected | Actual | Screenshot |
|---|---|---|---|
| `SELECT * FROM accounts` | Allowed | Allowed (5 rows, 6 columns, including `password_hash`) | `admin_02_select_accounts_allowed.png` |
| `SELECT * FROM audit_log` | Allowed | Allowed (5 rows, 5 columns) | `admin_03_select_audit_log_allowed.png` |
| `SELECT * FROM medical_records` | Allowed | Allowed (5 rows, 6 columns) | `admin_04_select_medical_records_allowed.png` |
| `SELECT * FROM patients` | Allowed | Allowed (5 rows, 8 columns, including `insurance_no`) | `admin_05_select_patients_allowed.png` |
| `SELECT * FROM staff` | Allowed | Allowed (5 rows, 7 columns, including `email` and `hire_date`) | `admin_06_select_staff_allowed.png` |
| `UPDATE accounts ...` | Allowed | Allowed (1 row changed, then restored) | `admin_02_select_accounts_allowed.png` (log lines) |

The eight admin queries were run together; each screenshot shows one result tab, and the log at the bottom shows `Rows matched: 1  Changed: 1` for both updates.

### 6.5 Observations

- Clicking a table in HeidiSQL runs `SELECT *`. A role that lacks even one column gets a "denied" error for the whole query. That is why column-restricted data is exposed through views.
- The sidebar of a session lists only the objects the user has privileges on. Doctors and nurses do not see `staff`, `accounts`, `audit_log`, `permissions` or `role_permissions`.
- Error 1142 means "command denied for table". Error 1054 means "unknown column", which is what the receptionist gets for `insurance_no` because the view does not contain it.
- Sidebar comparison: `sidebar_nurse_and_receptionist.png` and `sidebar_admin_and_doctor.png` show which objects each session can see. The receptionist sees the view `patient_contact` but not `patients` or `medical_records`. The doctor and the nurse see no `staff`, `accounts`, `audit_log`, `permissions` or `role_permissions`. The admin sees all 10 tables and both views.
- The view hides `insurance_no` from everyone who uses it, including the admin: `SELECT insurance_no FROM patient_contact` also fails with error 1054 for `admin_test` (`admin_extra_insurance_no_in_view.png`). The admin reads `insurance_no` from the `patients` table instead (`admin_05_select_patients_allowed.png`).
- With the `DENY` version of the grants, `SHOW TABLES` for the doctor and the nurse also lists the view `patient_contact`. The sidebar screenshots were taken before that change and do not show it.

### 6.6 Attacks against the DENY rules (sections F to J)

Sections F to J of `database/03_access_tests.sql` were run on MariaDB 13.1.1 and 13.1.2 with the `mariadb` command-line client, with the same results on both. There are no screenshots for them yet.

| Section | Run as | Attack | Result |
|---|---|---|---|
| F | root, then `dr_test` | Grant the denied `accounts` table back to the doctor in four ways (to `doctor`, to `hospital_staff`, to the user, and `SELECT ON *.*` to the user), then `FLUSH PRIVILEGES` | `SELECT * FROM accounts` is still denied (1142) |
| G | `dr_test` | `SET ROLE hospital_admin` | Denied (1959) |
| G | `dr_test` | `GRANT SELECT ON hospital.accounts TO doctor` | Denied (1142) |
| G | `dr_test` | `REVOKE DENY ALL PRIVILEGES ON hospital.accounts FROM hospital_staff` | Denied (1142) |
| G | `dr_test` | `SHOW GRANTS FOR hospital_staff` | Denied (1044) |
| H | `admin_test` | `SELECT COUNT(*) FROM audit_log` | Allowed |
| H | `admin_test` | `UPDATE`, `DELETE`, `TRUNCATE`, `DROP TABLE`, `ALTER TABLE`, `RENAME TABLE` and `CREATE TRIGGER` on `audit_log` | Denied (1142) |
| H | `admin_test` | `DROP DATABASE hospital` | Denied (1044) |
| H | `admin_test` | `REVOKE DENY UPDATE ON hospital.audit_log FROM hospital_admin` | Denied (1142) |
| I | root, then `dr_test` | Root creates a new table `hospital.salaries`, then the doctor reads it | Allowed. This is a gap, see section 9 |
| J | root, then `dr_test` | As F, but with only two of the grants (`accounts` to `doctor`, and `SELECT ON *.*` to the user) and without `FLUSH PRIVILEGES` | Allowed until `FLUSH PRIVILEGES` is run, then denied (1142). This is a gap, see section 9 |

## 7. Restoring the database

Restoring needs **two files, in this order**. The export does not contain users, roles, grants or denies.

1. If a `hospital` database already exists, run `DROP DATABASE hospital;` first.
2. Connected as root, open `hospital_full.sql` and execute it **once** (HeidiSQL: F9).
3. Open `database/02_roles_grants.sql` and execute it **once**.
4. Check the data:

```sql
USE hospital;
SELECT COUNT(*) FROM departments;      -- 8
SELECT COUNT(*) FROM roles;            -- 4
SELECT COUNT(*) FROM permissions;      -- 8
SELECT COUNT(*) FROM role_permissions; -- 20
SELECT COUNT(*) FROM staff;            -- 30
SELECT COUNT(*) FROM accounts;         -- 30
SELECT COUNT(*) FROM patients;         -- 200
SELECT COUNT(*) FROM appointments;     -- 501 (500 generated + 1 inserted by the receptionist test in 6.3)
SELECT COUNT(*) FROM medical_records;  -- 500
SELECT COUNT(*) FROM audit_log;        -- 1000
```

5. Check the access control with `SHOW GRANTS FOR receptionist;` (as root, so that the `DENY` lines are shown) and the tests in `database/03_access_tests.sql`.
6. To switch the test users to ED25519 authentication and required TLS, run `security/setup-hospital-users.sh` afterwards (see `security/README.md`). Running `database/02_roles_grants.sql` again resets the users to the demo passwords, so the setup script must then be run again.

To create a new export, connect as **root** (not as a test user, otherwise the export only contains what that user can see), right-click `hospital` → *Export database as SQL*, with Create for database and tables, Data = Insert, and check that the file contains `CREATE VIEW`.

## 8. Problems encountered and fixes

| Problem | Cause | Fix |
|---|---|---|
| Mockaroo dates rejected by MariaDB (`8/19/2026`) | MariaDB expects `YYYY-MM-DD` | Set the Mockaroo date format to `%Y-%m-%d` (datetimes: `%Y-%m-%d %H:%M:%S`), or use Find/Replace with regex `'(\d{1,2})/(\d{1,2})/(\d{4})'` → `'$3-$1-$2'` |
| `Can't create database 'hospital'; database exists` | Script was run a second time | Do not re-run `CREATE` scripts; check with `SHOW TABLES;` |
| Duplicate rows in `departments` and `roles` (48 and 24) | INSERT script was executed 6 times (F9 runs the whole tab) | `SET FOREIGN_KEY_CHECKS = 0; TRUNCATE TABLE ...; SET FOREIGN_KEY_CHECKS = 1;` then insert again |
| Duplicate rows in `permissions` (16 instead of 8) | INSERT was executed twice | `DELETE FROM permissions WHERE permission_id > 8; ALTER TABLE permissions AUTO_INCREMENT = 9;` after checking that `role_permissions` did not use the IDs above 8 |
| Missing tables (`role_permissions`, `medical_records`, `audit_log`) | Schema script stopped partway | Created the missing tables separately |
| `staff` count stayed 0 | Inserts had not succeeded because of the date format and missing `USE hospital;` | Fixed dates, added `USE hospital;` as line 1, ran once |
| HeidiSQL export: `Unable to create directory` | Filename had no folder path | Chose a full path with the folder button |
| "SELECT command denied" when clicking `staff` or `patients` as a restricted user | HeidiSQL runs `SELECT *`, which includes columns the role may not read | Expected behaviour; test in a query tab, and use the views `staff_directory` and `patient_contact` |
| Test script stopped at the first denied query | HeidiSQL runs the whole tab with F9, and an error stops the run | One query per tab for DENIED tests |

## 9. Limitations

- MariaDB has no row-level security. A receptionist who may update `patient_contact` can update any patient's row. Restricting rows would need an additional view with a `WHERE` condition.
- A view hides columns but not rows, and it works because it runs with its creator's privileges.
- The `permissions` and `role_permissions` tables document the model; MariaDB itself does not read them. The privileges in `database/02_roles_grants.sql` must be kept in line with them by hand.
- The demo passwords are fake and stored in the script on purpose; a real system would never do this. `security/setup-hospital-users.sh` replaces them.
- **New tables are readable by default.** `hospital_staff` has `SELECT` on `hospital.*`, so a table added later can be read by doctors, nurses and receptionists until a `DENY` is added for it (test section I).
- **A deny can be skipped until the privileges are reloaded.** On MariaDB 13.1.1 and 13.1.2, with a grant on `accounts` to the role `doctor` plus `SELECT ON *.*` to the user, the doctor could read `accounts` until `FLUSH PRIVILEGES` was run (test section J). `database/02_roles_grants.sql` therefore ends with `FLUSH PRIVILEGES`, and it should be run again after every later `GRANT`, `DENY` or `REVOKE DENY`.
- The admin cannot change or delete existing audit log rows, but can still insert new ones.
- root is not restricted by these roles and can remove any deny with `REVOKE DENY`.
