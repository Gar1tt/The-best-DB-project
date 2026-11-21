# Hospital Database: Setup Documentation

Part of the project **Authentication and Access Control of a Hospital Database** (MariaDB).
This document covers the database structure, the generated test data, and the roles and privileges.

> All data in this database is **fake** (generated with Mockaroo). No real patient data is used.

## Repository files

| File | Purpose |
|---|---|
| `hospital_full.sql` (repository root) | Full export of the database: schema, views and data |
| `database/02_roles_grants.sql` | Roles, views, test users and `GRANT` statements |
| `database/03_access_tests.sql` | Allowed and denied queries used to test each role |
| `database/screenshots/` | Evidence of the test results |
| `database_setup.md` | This document |
| `docker-compose.yml`, `.env.example` | Docker setup for MariaDB (see section 7) |

## 1. Environment

| Item | Value |
|---|---|
| DBMS | MariaDB 13.1.1 |
| Client | HeidiSQL 12.20 |
| Database name | `hospital` |
| Test data generator | [Mockaroo](https://www.mockaroo.com) |
| Docker setup | `docker-compose.yml`: container `hospital-db`, MariaDB 13.1, port `127.0.0.1:3306` |

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

MariaDB has **no `DENY` statement**. Access is denied by not granting a privilege (everything is forbidden by default), and `REVOKE` removes a privilege that was granted earlier. This project therefore uses three techniques:

1. **Withholding grants**: a role with no privilege on a table cannot even see it in the table list.
2. **Views**: a view exposes only safe columns, and the role is granted the view instead of the table.
3. **Roles**: privileges are granted to roles, and roles are assigned to users.

The `roles`, `permissions` and `role_permissions` tables describe the access model in the data. The actual enforcement is done by MariaDB with `CREATE ROLE`, `GRANT` and `CREATE USER` in `02_roles_grants.sql`.

### 5.1 Views

| View | Based on | Columns shown | Hidden columns |
|---|---|---|---|
| `staff_directory` | `staff` | staff_id, first_name, last_name, role_id, dept_id | email, hire_date |
| `patient_contact` | `patients` | patient_id, first_name, last_name, birth_date, gender, phone, address | insurance_no |

A view runs with the privileges of its creator (root), so users of the view need no rights on the underlying table. This makes the view definition the security boundary: it must list only safe columns.

### 5.2 Privileges per MariaDB role

| Object | doctor | nurse | receptionist | hospital_admin |
|---|---|---|---|---|
| `patients` | SELECT | SELECT | none | ALL |
| `patient_contact` (view) | none | none | SELECT, INSERT, UPDATE | ALL |
| `medical_records` | SELECT, INSERT, UPDATE | SELECT | none | ALL |
| `appointments` | SELECT | SELECT, INSERT, UPDATE | SELECT, INSERT, UPDATE | ALL |
| `staff` | none | none | none | ALL |
| `staff_directory` (view) | SELECT | SELECT | SELECT | ALL |
| `departments`, `roles` | SELECT | SELECT | SELECT | ALL |
| `accounts`, `audit_log` | none | none | none | ALL |
| `permissions`, `role_permissions` | none | none | none | ALL |

### 5.3 Test users (demo passwords only)

| User | Password | Role |
|---|---|---|
| `dr_test` | `Doctor!Test1` | doctor |
| `nurse_test` | `Nurse!Test1` | nurse |
| `reception_test` | `Reception!Test1` | receptionist |
| `admin_test` | `Admin!Test1` | hospital_admin |

Each user exists for two hosts, `'localhost'` and `'%'`, with the same password and role:

- `'localhost'` is used on a local MariaDB, or by a client running inside the container.
- `'%'` is used by a client on the host machine (for example HeidiSQL) connecting to the Docker container. Such a connection reaches the container from a Docker address, not from `localhost`, so a user created only for `'localhost'` would get "Access denied". `CURRENT_USER()` then shows `dr_test@%`.

Each user has the role set as the default role, so it is active at login. The credentials are fake and for testing only. Do not use real passwords in the repository.

The compose file loads the `auth_ed25519` plugin for the authentication part of the project. The demo users here use MariaDB's default password authentication. Roles and grants work the same with any authentication plugin.

## 6. Testing

Each user was tested in a separate HeidiSQL session (host `127.0.0.1`). The queries are in `03_access_tests.sql`. A denied query that gets denied counts as a pass. Screenshots are in `screenshots/`.

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

## 7. Restoring the database

Restoring needs **two files, in this order**, both run as root. The export does not contain users, roles or grants.

1. `hospital_full.sql`: tables, views and data.
2. `database/02_roles_grants.sql`: roles, views, test users and privileges.

Run each file **once**. `hospital_full.sql` inserts the data again if it is run twice on a database that already has tables.

### 7.1 With Docker (project setup)

1. Copy `.env.example` to `.env` and set `DB_ROOT_PASSWORD`. Do not commit `.env`.
2. Start the container: `docker compose up -d`. The first start creates an empty `hospital` database (`MARIADB_DATABASE`).
3. Load the two files, either with a client or on the command line.
   - **HeidiSQL:** new session with host `127.0.0.1`, port `3306`, user `root` and the password from `.env`. Open `hospital_full.sql`, press F9 once, then do the same with `database/02_roles_grants.sql`.
   - **Command line** (works in PowerShell and bash; it asks for the root password each time):

```
docker cp hospital_full.sql hospital-db:/tmp/hospital_full.sql
docker cp database/02_roles_grants.sql hospital-db:/tmp/02_roles_grants.sql
docker exec -it hospital-db mariadb -uroot -p -e "source /tmp/hospital_full.sql"
docker exec -it hospital-db mariadb -uroot -p -e "source /tmp/02_roles_grants.sql"
```

4. Log in as a test user from the host: host `127.0.0.1`, port `3306`, for example user `dr_test` with `Doctor!Test1`. Then follow `database/03_access_tests.sql`.
5. To load again from scratch, either run `DROP DATABASE hospital; CREATE DATABASE hospital;` and load both files again, or run `docker compose down -v` (this deletes all data in the volume) followed by `docker compose up -d`.
6. If port 3306 is already in use, for example by a MariaDB installed on the computer, stop that server or change the mapping in `docker-compose.yml` to `"127.0.0.1:3307:3306"` and connect to port 3307.

### 7.2 With a local MariaDB (without Docker)

1. If a `hospital` database already exists, run `DROP DATABASE hospital;` first.
2. Connected as root, open `hospital_full.sql` and execute it once (HeidiSQL: F9).
3. Open `database/02_roles_grants.sql` and execute it once.

### 7.3 Checking the result

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
SHOW GRANTS FOR receptionist;
```

The counts can differ slightly if the access tests were run before the export (a few test rows were changed or added).

### 7.4 Creating a new export

Connect as **root** (not as a test user, otherwise the export only contains what that user can see). Right-click `hospital`, choose *Export database as SQL*, tick only the `hospital` database, with Create for database and tables and Data = Insert. In the file, `Dumping structure for view` should appear twice. HeidiSQL also writes a temporary placeholder table for each view, so the file contains 12 `CREATE TABLE` lines for the 10 real tables.

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
| A test user cannot log in from a client on the host when MariaDB runs in Docker (`Access denied` for a Docker address) | The user existed only for `'localhost'`, but the connection arrives from a Docker address | `02_roles_grants.sql` creates every test user for `'localhost'` and `'%'` |

## 9. Limitations

- MariaDB has no row-level security. A receptionist who may update `patient_contact` can update any patient's row. Restricting rows would need an additional view with a `WHERE` condition.
- A view hides columns but not rows, and it works because it runs with its creator's privileges.
- The `permissions` and `role_permissions` tables document the model; MariaDB itself does not read them. The privileges in `02_roles_grants.sql` must be kept in line with them by hand.
- The demo passwords are fake and stored in the script on purpose; a real system would never do this.
- The `'%'` test users accept connections from any address. This is acceptable here only because `docker-compose.yml` publishes the port on `127.0.0.1` and the passwords are demo values. A real system would restrict the allowed hosts and use strong secrets.

## 10. Status

- [x] Tables created and filled with fake data
- [x] `permissions` and `role_permissions` defined by hand
- [x] MariaDB roles created (`02_roles_grants.sql`)
- [x] `GRANT` privileges per role, with the views `staff_directory` and `patient_contact`
- [x] Test users created and roles assigned
- [x] Allowed and denied queries tested per user (`03_access_tests.sql`)
- [x] Results tables in section 6 filled in with screenshot names
- [ ] Final `hospital_full.sql` exported as root (with `CREATE VIEW`) and pushed to the repository
