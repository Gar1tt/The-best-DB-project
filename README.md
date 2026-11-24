# Hospital Database: Authentication and Access Control

This database course project uses MariaDB 13.1 and a Python command-line app to demonstrate hospital access control on generated data. The **Hospital Keycard Terminal** gives every account the same menu, but the database decides which actions succeed. The app shows the signed-in account, its active role, the TLS connection details, and a live read-access keycard.

**Team:** Enrico, Dushko, and Huseyn.

## Access model

The doctor, nurse, and receptionist inherit `hospital_staff`. It gives them schema-wide `SELECT` with explicit `DENY` exceptions for tables such as `accounts`, `staff`, and `audit_log`. The receptionist has extra denials on `patients` and `medical_records`; the hospital admin has separate denials that protect existing audit rows. See the [full privilege matrix](DATABASE_SETUP.md#52-roles-grants-and-denies) and the [MariaDB `DENY` reference](https://mariadb.com/docs/server/reference/sql-statements/account-management-sql-statements/deny).

| Login | Default role | Example allowed action | Example blocked action |
|---|---|---|---|
| `dr_test` | `doctor` | Read and add medical records | Read the `accounts` table |
| `nurse_test` | `nurse` | Read medical records and book appointments | Add a medical record |
| `reception_test` | `receptionist` | Look up and update contact details through `patient_contact` | Read insurance numbers or medical records |
| `admin_test` | `hospital_admin` | Read the audit log | Update or delete existing audit rows |

The `patient_contact` and `staff_directory` views expose selected columns without giving staff access to the underlying tables where those tables are denied. The schema's `roles` and `permissions` tables describe the model; the enforcement comes from MariaDB roles, `GRANT`, `DENY`, and the view definitions, not from those tables or Python menu logic.

## Set up from scratch

Use a Bash shell with Git, Docker with Compose v2, OpenSSL 3, and Python 3.10 or newer with `venv`. After cloning, run all shell commands from the repository root. Use a fresh demo database volume and keep the service local; the supplied Compose file publishes MariaDB only on `127.0.0.1:3306`.

### Start MariaDB

```bash
git clone https://github.com/Gar1tt/The-best-DB-project.git
cd The-best-DB-project
(umask 077; cp -n .env.example .env)
```

Open `.env` and replace `change-me` with a strong local password for MariaDB root. Keep `.env` private and out of Git. Start the container and check that MariaDB is ready before importing the schema.

```bash
docker compose up -d --build
docker compose exec db healthcheck.sh --connect --innodb_initialized
```

If the [MariaDB readiness check](https://mariadb.com/docs/server/server-management/automated-mariadb-deployment-and-administration/docker-and-mariadb/using-healthcheck-sh) fails while the server is starting, check `docker compose logs db` and retry. The base Compose file builds from MariaDB's upstream 13.1 directory; it does not pin an exact patch release.

### Import the schema and roles

Compose creates an empty `hospital` database. Run this import **once** to load the schema and generated data first, then the roles and demo accounts. Enter your `.env` root password when prompted.

```bash
docker compose cp hospital_full.sql db:/tmp/hospital_full.sql
docker compose cp database/02_roles_grants.sql db:/tmp/02_roles_grants.sql
docker compose exec db mariadb -u root -p --abort-source-on-error \
  -e $'SOURCE /tmp/hospital_full.sql\nSOURCE /tmp/02_roles_grants.sql\nSELECT VERSION() AS mariadb_version;\nSELECT COUNT(*) AS patients FROM hospital.patients;'
```

Check that the command finishes without SQL errors, reports MariaDB `13.1.x`, and shows **200 patients**. Do not rerun the dump against a populated database. For a restore rather than a fresh install, see [database restore notes](DATABASE_SETUP.md#7-restoring-the-database).

### Configure the ED25519 accounts

```bash
bash security/setup-hospital-users.sh
```

Enter your root password, then choose a password for each of the four demo accounts. Use at least eight characters; the script accepts letters, numbers, and `_!@#%^.*-`. It switches both account host definitions to ED25519 with `REQUIRE SSL`, without changing their roles. Rerunning `02_roles_grants.sql` resets the accounts to their initial demo passwords, so rerun the authentication setup if you reapply the role script.

At this point, you can verify the base server setup using the repository's read-only integration suite. Run this before the next step: the suite uses MariaDB's native client TLS verification, while the app below uses a separate, explicitly trusted CA. Enter the four demo passwords in the order prompted.

```bash
bash security/tests/hospital-integration-tests.sh
```

The expected summary is `19 passed, 0 failed`. These checks cover default roles, allowed and denied queries, verified TLS, and refusal of logins without TLS. See the [security setup notes](security/README.md) for details.

### Configure TLS for the Python app

The app verifies the server certificate against a trusted CA and checks that it matches the host you connect to. Generate a local demo CA and a server certificate for `127.0.0.1` and `localhost`. Keep the CA key and server key private; the repository ignores `certs/`.

```bash
mkdir -p certs
(
  set -e
  umask 077
  openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 365 \
    -subj '/CN=Hospital Demo CA' \
    -addext 'basicConstraints=critical,CA:TRUE' \
    -addext 'keyUsage=critical,keyCertSign,cRLSign' \
    -keyout certs/ca.key -out certs/ca.pem
  openssl req -new -newkey rsa:2048 -nodes \
    -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' \
    -keyout certs/server.key -out certs/server.csr
  openssl x509 -req -in certs/server.csr -CA certs/ca.pem -CAkey certs/ca.key \
    -CAcreateserial -days 90 -sha256 -copy_extensions copy -out certs/server.pem
)
```

Copy the public CA certificate, the server certificate, and the server key into the database volume. Do **not** copy `certs/ca.key`. The override restarts MariaDB with these files and keeps the imported data and accounts.

```bash
docker compose exec -T -u root db mkdir -p /var/lib/mysql/hospital-tls
docker compose cp certs/ca.pem db:/var/lib/mysql/hospital-tls/
docker compose cp certs/server.pem db:/var/lib/mysql/hospital-tls/
docker compose cp certs/server.key db:/var/lib/mysql/hospital-tls/
docker compose exec -T -u root db chown -R mysql:mysql /var/lib/mysql/hospital-tls
docker compose exec -T -u root db chmod 600 /var/lib/mysql/hospital-tls/server.key
docker compose -f docker-compose.yml -f app/compose.tls.yml up -d
docker compose exec db healthcheck.sh --connect --innodb_initialized
```

Use both Compose files on later `up` commands so the server keeps using the demo certificate. For an existing server with a certificate you already trust, use its CA file and the hostname on its certificate instead of generating new ones.

### Run the terminal app

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r app/requirements.txt
.venv/bin/python app/hospital.py --ca certs/ca.pem --user reception_test
```

Enter the receptionist password from the ED25519 setup. The app should show `role receptionist`, a TLS version and cipher, and confirmation that the certificate matched the supplied CA and host. Add `keycard` to print the read-access card and exit, or `connection` to show only the connection details.

## Demo walkthrough

Try the same action with different accounts so it is clear that MariaDB enforces the permissions. Use patient ID `1` and staff ID `1` for actions that need IDs. Writes require confirmation and change the generated demo data.

1. **Reception:** Open the keycard. `patient_contact` should show `OPEN`; `patients` and `medical_records` should show `LOCKED`. Use `Find a patient`, then try `Insurance number of a patient` with the same account.
2. **Doctor and nurse:** Choose `Add a diagnosis` as `dr_test`, then try that same menu action as `nurse_test`. The doctor can save it; MariaDB refuses the nurse. The nurse can still read medical records and choose `Book an appointment`.
3. **Admin:** Open `Login history (audit log)` as `admin_test`. The log is readable, but the role's denials protect existing rows from edits and deletions. The app does not offer an audit-log editing action.

## What each control protects

| Control | What the team checked | Expected outcome or recorded result |
|---|---|---|
| ED25519 authentication | Sign in with an incorrect password | MariaDB refuses the login. All four configured accounts can sign in with their correct passwords. |
| Server-side `REQUIRE SSL` | Connect without TLS using a valid demo account | MariaDB refuses the login, even with the correct password. |
| Client-side certificate verification | Connect with an unrelated CA or a hostname not listed on the certificate | The Python client refuses the connection. A correct connection shows the TLS version and cipher. |
| Database roles | Try adding a diagnosis as a nurse or using an admin role not assigned to the user | MariaDB refuses the write or role activation. |
| Inherited `DENY` | Verify that a conflicting grant does not give the doctor read access to `accounts` after privileges are reloaded | The explicit denial still wins. |
| Restricted views | Look up a patient as reception, then request insurance details from the base table | The contact view works; the base-table lookup is denied. |
| Audit-log `DENY` | Verify that the hospital admin can read audit history but cannot update or delete existing rows | Reads work; the tested changes are denied. |

See [security test results](security/results.md) and [database test notes](DATABASE_SETUP.md#6-testing) for the underlying evidence. The Python app was also verified on a local MariaDB 13.1.1 server with all four accounts, including rejection of an incorrect password, an unrelated CA and a mismatched hostname. The [app pull request](https://github.com/Gar1tt/The-best-DB-project/pull/6) records that the Docker TLS override was not part of that test run. The SQL access-test file contains a mix of accounts and some state-changing checks; do not run the entire file as root or against a database you need to keep.

## What remains unprotected

- **Row access:** The project does not enforce per-patient access. For example, reception can update contact information for any patient through the contact view.
- **New tables:** The inherited schema-wide read grant covers new tables unless their access is explicitly restricted. Review privileges when adding a table.
- **Privilege changes:** Testing on 13.1.1 and 13.1.2 found that some privilege changes were not enforced as expected until a privilege reload. The setup SQL ends with `FLUSH PRIVILEGES`; repeat it after access-control changes and verify the affected roles.
- **Audit integrity and root:** The hospital admin can still insert audit rows. MariaDB root is not constrained by the hospital roles. This is not a tamper-proof audit system.
- **Production security:** This is a local demo, not a deployment for real patient data. It does not provide individual staff identity management, credential rotation, or operational monitoring.

## Troubleshooting

- **Port in use:** Free host port `3306`, or change only the host-side port in `docker-compose.yml` and pass `--port` to the app. Keep the host binding on `127.0.0.1`.
- **Login denied:** Use a demo account and the password entered during ED25519 setup, not the root password. If you reapplied the role script, run the auth setup again.
- **Certificate verification failed:** Check that the override is active, the certificate is current, and `--ca` points to the correct CA. Use `127.0.0.1` or `localhost` with the certificates above. Do not disable verification.
- **Returning to a running setup:** `docker compose stop db` preserves your data. Restart with both Compose files. Editing `.env` does not change the root password on an already initialized volume.

## Repository guide

| Path | Purpose |
|---|---|
| [`hospital_full.sql`](hospital_full.sql) | Schema, generated data, and views |
| [`database/02_roles_grants.sql`](database/02_roles_grants.sql) | Roles, test accounts, grants, and denies |
| [`database/03_access_tests.sql`](database/03_access_tests.sql) | SQL permission checks and documented limitations |
| [`security/`](security/) | ED25519 setup, integration tests, and test notes |
| [`app/`](app/) | Python terminal app, dependency file, and TLS Compose override |
| [`DATABASE_SETUP.md`](DATABASE_SETUP.md) | Schema details, privilege matrix, restore steps, and SQL test results |
