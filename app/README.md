# Hospital Keycard Terminal

Everyone sees the same doors, but MariaDB decides which ones open. The Python app logs in as a hospital account, shows its active role and TLS cipher, and runs real hospital workflows. The keycard checks read access without retrieving rows. Use the generated course data only.

## Set up the database

Follow [database setup](../DATABASE_SETUP.md#7-restoring-the-database) and [security setup](../security/README.md#2-setting-up-authentication). Import `hospital_full.sql`, apply `database/02_roles_grants.sql`, then configure the four ED25519 accounts with `security/setup-hospital-users.sh`. Start the base Compose service before the following steps.

## Set up verified TLS

The Python client requires a trusted CA and a matching hostname or IP. For the local Compose demo, create a CA and sign a certificate for `127.0.0.1` and `localhost`. Run these commands from the repository root using a shell with OpenSSL. Run them once per local database; for an existing server with a trusted certificate, skip this section and use its CA file instead.

```sh
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

Copy only the certificates and the server key into the database volume. Keep the CA private key local. The repository ignores `certs/`.

```sh
docker compose exec -T -u root db mkdir -p /var/lib/mysql/hospital-tls
docker compose cp certs/ca.pem db:/var/lib/mysql/hospital-tls/
docker compose cp certs/server.pem db:/var/lib/mysql/hospital-tls/
docker compose cp certs/server.key db:/var/lib/mysql/hospital-tls/
docker compose exec -T -u root db chown -R mysql:mysql /var/lib/mysql/hospital-tls
docker compose exec -T -u root db chmod 600 /var/lib/mysql/hospital-tls/server.key
docker compose -f docker-compose.yml -f app/compose.tls.yml up -d
```

Use both Compose files on subsequent `up` commands to retain this TLS configuration. The override keeps the database volume and ED25519 plugin. It does not change the roles or import any data.

## Run the terminal app

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r app/requirements.txt
.venv/bin/python app/hospital.py --ca certs/ca.pem --user reception_test
```

The password prompt hides your input. There is no password option or password file. To print the access card and quit, add `keycard` to the command; to show only the connection details, add `connection` instead. The app uses the driver's ED25519 support with the accounts configured by the security setup script.

## Demo walkthrough

| Account | Try this | Expected result |
|---|---|---|
| `reception_test` | Compare `Find a patient` with `Insurance number of a patient` | The contact view opens; the insurance lookup is locked. |
| `dr_test` | Open the `Medical file of a patient` or choose `Add a diagnosis` | The medical file opens; the doctor can save a diagnosis. |
| `nurse_test` | Choose `Book an appointment` | The nurse can save an appointment. |
| `admin_test` | Open `Login history (audit log)` | The log is readable; the menu does not offer audit-log edits. |

Writes require confirmation and modify the demo database. A `LOCKED by the database` message is a MariaDB permission error, not a check against a list of allowed roles in Python. The keycard reports read access only, not write access or row-level permissions. The CLI does not replace the existing [database and security test suites](../DATABASE_SETUP.md).
