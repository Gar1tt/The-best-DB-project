# Database setup and privilege model

Start with the [main setup instructions](README.md#start-from-a-fresh-clone). The bootstrap imports [`hospital_full.sql`](hospital_full.sql) and [`database/02_roles_grants.sql`](database/02_roles_grants.sql) once, then creates the four password-prompted ED25519 accounts and checks their effective access.

## Data and schema

The original SQL export is unchanged. It contains the hospital schema, synthetic patients and staff, appointment and medical-record data, and two views. The original schema description, data generation notes, and screenshots are preserved in the [prior revision](https://github.com/Gar1tt/The-best-DB-project/blob/ff3971d1591df1d4b47410e047ee70cf7e989e78/DATABASE_SETUP.md).

| Area | Tables | Purpose |
|---|---|---|
| People and departments | `patients`, `staff`, `departments` | Patient register, staff directory, and departments |
| Care and scheduling | `medical_records`, `appointments` | Patient diagnoses, notes, and appointments linked to staff and patients |
| Seeded identity and history | `accounts`, `roles`, `permissions`, `role_permissions`, `audit_log` | Sample organizational data and historical events; not the application logins or effective ACL |
| Live audit | `hospital_audit.events` | Metadata about successful app writes, recorded by MariaDB after setup |

The role SQL replaces `patient_contact` and `staff_directory` with versions owned by a locked definer scoped to the columns they need. It introduces `staff_login_directory` so the operations reviewer can see a staff login summary without seeing stored password hashes in `accounts`.

## Effective privileges

`hospital_staff` grants reads on explicitly listed shared tables and views. It does not grant `SELECT` over the schema; an added table is closed by default. It explicitly denies the underlying accounts, staff table, and audit records.

| Object or operation | Doctor | Nurse | Receptionist | Hospital admin |
|---|---|---|---|---|
| `patient_contact` | Read | Read permitted columns only | Read; update `phone` only | Not granted |
| `patients`, including insurance | Read | Denied | Denied | Not granted |
| `medical_records` | Read and insert supported columns | Denied | Denied | Not granted |
| `appointments` | Read | Read and book | Read and book | Not granted |
| `staff_directory` and lookup tables | Read | Read | Read | Read |
| Raw `accounts` table | Denied | Denied | Denied | Denied |
| `staff_login_directory` | Not granted | Not granted | Not granted | Read |
| Seeded `audit_log` and live `hospital_audit.events` | Denied | Denied | Denied | Read; no manual append, edit, or deletion |

The nurse inherits normal `SELECT` on `patient_contact` and has an explicit `DENY SELECT` for `birth_date`, `gender`, and `address`. That is a real overlap between an inherited grant and an explicit denial; the database resolves it even when the user connects directly, outside the CLI. Use the [verifier](app/verify_demo.py) for the current checks.

## Audit records

MariaDB triggers record diagnosis creation, appointment booking, and changes to patient phones. The locked audit writer can insert into `hospital_audit.events` from those triggers. Each event records a login, timestamp, action, and object ID, not a diagnosis, phone number, or other content. The app's admin opens the live log using menu option 13.

The role and account provisioning applies `FLUSH PRIVILEGES` as part of setup. Re-check the affected roles after future privilege changes. See [what remains unprotected](README.md#what-remains-unprotected) for patient scope and audit limitations.
