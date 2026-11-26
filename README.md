# Hospital Database: Authentication and Access Control

The Hospital Keycard Terminal is a Python app for a synthetic hospital database. Everyone sees the same menu, but MariaDB evaluates each account's permissions. The app shows its active role and verified TLS connection, and the database records successful clinical and scheduling writes in a separate audit schema.

**Team:** Enrico, Dushko, and Huseyn.

## Start from a fresh clone

Install Git, Docker with Compose v2 and BuildKit, Python 3.10+ with `venv`, and OpenSSL 3. Use a local terminal and an empty demo volume. This project is for generated course data, not patient information.

```bash
git clone https://github.com/Gar1tt/The-best-DB-project.git
cd The-best-DB-project
python3 security/demo.py setup
```

Choose four different demo passwords when prompted. Input is hidden. Use 12–128 characters from letters, numbers, and `_!@#%^.*-`. The script generates an ignored `.env` file for MariaDB root if one does not exist; it does not save the app passwords. Docker builds the pinned upstream MariaDB **13.1.2** recipe and publishes the database only on `127.0.0.1:3306`.

The setup command generates and installs a local TLS certificate, imports the schema and roles, creates the ED25519 accounts locked until their roles are assigned, and runs the app verification. The last line should be `PASS: all selected app and database checks`. On an empty demo, verification adds one sample diagnosis, one appointment, and corresponding audit events; it restores the test patient's original phone number.

If you already ran the old setup, use a **separate fresh volume** for this version. The bootstrap is not a migration tool: it stops rather than replacing existing hospital tables. Use a new checkout with `COMPOSE_PROJECT_NAME=hospital-review` and, if the old server is still running, set a different `HOSPITAL_DB_PORT`.

## Open the terminal app

```bash
.venv/bin/python app/hospital.py --ca certs/ca.pem --user reception_test
```

Use the receptionist password from setup, not the root password. The header shows the active role, TLS version, cipher, and verification of the certificate against the supplied CA and host. Append `keycard` to print read access or `connection` to print only the TLS and session details. On Windows, the virtual environment interpreter is `.venv/Scripts/python.exe`.

| Account | Menu action | Expected result |
|---|---|---|
| `reception_test` | **2** Find a patient, then **3** look up insurance for patient `1` | The contact lookup works; the insurance lookup is locked. **8** changes the phone without granting permission to edit the rest of the contact record. |
| `dr_test` | **5** Add a diagnosis for patient `1` and staff `1` | The doctor can save a diagnosis. Confirm with `y` to write it. |
| `nurse_test` | Try the same **5** action, then **7** Book an appointment | MariaDB refuses the diagnosis, but allows the appointment. Use a date in `YYYY-MM-DD HH:MM` format. |
| `admin_test` | **13** Live audit history | The admin can see events attributed to the doctor and nurse. The role cannot append, edit, or delete events. **10** shows the separate, historical seed data. |

Choose `0` to exit before signing in as a different account. Every menu is the same; `LOCKED by the database` means the database refused the operation. The keycard measures object read access, not access to every column or write access.

## Verify the running demo

```bash
python3 security/demo.py verify
```

Enter the same four passwords. This runs the non-writing checks on an already provisioned setup. The fresh setup also checks the normal write workflows and verifies that the resulting audit records match their actors. The [verification source](app/verify_demo.py) makes the expected outcomes and failure conditions explicit.

| Control | What verification shows |
|---|---|
| ED25519 | The database reports `ed25519` for all four accounts; correct credentials work and an incorrect password is refused. |
| Required TLS | The same local account connects with verified TLS and is refused without TLS. Connection or setup errors are not treated as an expected refusal. |
| Verified server identity | The Python connection accepts the correct CA and host, rejects an unrelated CA and a hostname mismatch, and reports the actual TLS version and cipher. |
| Roles and `DENY` | The nurse inherits access to the contact view, but a column `DENY` blocks birth date, gender, and address. The doctor can write diagnoses; the nurse cannot. |
| Restricted views | Reception can read contact details and change the phone, but cannot read insurance from the base table or edit the address. |
| Live audit | MariaDB records successful app writes. The admin can read events but cannot change them, and the nurse cannot read the audit table. |

## What remains unprotected

- **Patient assignments:** Roles restrict tables, views, and columns, not which individual patients a staff member may serve. All test accounts represent demo roles rather than named employees.
- **Audit scope:** Triggers cover diagnosis creation, appointment booking, and changes to a patient's phone. They record actor, time, action, and object ID, not medical content, unsuccessful actions, reads, or logins. Root can still modify the configuration or the audit table.
- **Operational security:** The server is a local demo. Do not expose it publicly, reuse demo credentials, or use the demo CA for other systems. Keep `.env` and the private keys on your machine.

## Stop or restart

`docker compose stop db` preserves the volume. Restart a configured demo with `docker compose -f docker-compose.yml -f app/compose.tls.yml up -d db`. If host port `3306` is in use, export `HOSPITAL_DB_PORT` before setup and pass the matching `--port` to the app. Running with the TLS override is required after setup.

If setup fails, check `docker compose logs db` and the first failed step. If an import was interrupted, use a fresh demo volume rather than rerunning the import against partial data. Do not remove a volume you need to keep.

## Project files

- **[Database setup](DATABASE_SETUP.md):** Schema, current privileges, and how the audit records are generated.
- **[Security setup](security/README.md):** Provisioning, trust model, and what the verifier checks.
- **[Verification notes](security/results.md):** Tested environment, outcomes, and historical evidence.
- **[Python app](app/README.md):** Terminal commands and demo workflows.
