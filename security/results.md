# Verification notes

## Current implementation

The revised schema, role SQL, ED25519 account provisioning, local CA, and Python verifier were exercised on a fresh **MariaDB 13.1.2** instance. The database in that run was a native sandbox process, not the Compose container.

| Check | Observed locally |
|---|---|
| ED25519/TLS connection and role | Four expected roles connected over TLS 1.3. |
| Refused connections | Incorrect credentials, TLS disabled, an unrelated CA, and a hostname mismatch were rejected. |
| Restricted access | Reception could use the contact view but not access insurance or edit the address; nursing could not read the restricted clinical data or the denied contact column. |
| App write and audit | Doctor diagnosis, nurse appointment, and receptionist phone updates created attributable audit events. Admin could read them, not modify them. |

Use `python3 security/demo.py setup --automated` to verify the Docker sequence on a disposable demo volume. That mode uses ephemeral test passwords and is not for interactive demos. The regular `setup` command runs the same checks with passwords you choose.

## Earlier evidence

The [previous results page](https://github.com/Gar1tt/The-best-DB-project/blob/ff3971d1591df1d4b47410e047ee70cf7e989e78/security/results.md) covers the earlier MariaDB 13.1.1 native-client checks. The existing screenshots show the original permission model, not the current one.
