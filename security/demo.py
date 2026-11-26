"""Provision or verify the local hospital demo. Never stores staff passwords."""

import argparse
import getpass
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import time
import warnings


ROOT = Path(__file__).resolve().parents[1]
COMPOSE = ["docker", "compose", "-f", "docker-compose.yml"]
TLS_COMPOSE = COMPOSE + ["-f", "app/compose.tls.yml"]
TLS_DIR = "/var/lib/mysql/hospital-tls"
ROLES = {
    "dr_test": "doctor",
    "nurse_test": "nurse",
    "reception_test": "receptionist",
    "admin_test": "hospital_admin",
}
DB_VERSION = "13.1.2"
VENV_PYTHON = ROOT / ".venv" / (
    "Scripts/python.exe" if os.name == "nt" else "bin/python"
)


def run(*command, input_text=None, capture=False):
    result = subprocess.run(
        command, cwd=ROOT, input=input_text, stdout=subprocess.PIPE if capture else None,
        check=True, text=True,
    )
    return result.stdout.strip() if capture else None


def passwords(automated=False):
    if automated:
        return {name: secrets.token_hex(24) for name in ROLES}
    result = {}
    with warnings.catch_warnings():
        warnings.simplefilter("error", getpass.GetPassWarning)
        for name in ROLES:
            value = getpass.getpass(f"Password for {name}: ")
            if not re.fullmatch(r"[A-Za-z0-9_!@#%^.*-]{12,128}", value):
                raise ValueError("Use 12–128 characters: letters, numbers, _!@#%^.*-")
            if value in result.values():
                raise ValueError("Choose a different password for each demo role")
            result[name] = value
    return result


def account_sql(values):
    """Build SQL for the four fixed demos. Values must pass the strict allowlist."""
    lines = []
    for name, role in ROLES.items():
        value = values[name]
        if not re.fullmatch(r"[A-Za-z0-9_!@#%^.*-]{12,128}", value):
            raise ValueError("Invalid demo password")
        account = f"'{name}'@'%'"
        # Keep logins locked until their role and default are installed.
        lines += [
            f"CREATE USER {account} IDENTIFIED VIA ed25519 USING PASSWORD('{value}') REQUIRE SSL ACCOUNT LOCK;",
            f"GRANT `{role}` TO {account};",
            f"SET DEFAULT ROLE `{role}` FOR {account};",
        ]
    lines.append("FLUSH PRIVILEGES;")
    lines.extend(f"ALTER USER '{name}'@'%' ACCOUNT UNLOCK;" for name in ROLES)
    return "\n".join(lines) + "\n"


def root_sql(sql, *, tls=False):
    # Root connects over the container socket. SQL goes through stdin, never argv.
    return run(
        *(TLS_COMPOSE if tls else COMPOSE), "exec", "-T", "db", "sh", "-ec",
        'export MYSQL_PWD="$MARIADB_ROOT_PASSWORD"; exec mariadb --protocol=socket '
        '--user=root --batch --skip-column-names --skip-print-query-on-error',
        input_text=sql, capture=True,
    )


def check_accounts():
    actual = root_sql(
        "SELECT User, Host, plugin, ssl_type FROM mysql.user "
        "WHERE User IN ('dr_test','nurse_test','reception_test','admin_test') "
        "ORDER BY User, Host;\n", tls=True,
    ).splitlines()
    expected = [f"{name}\t%\ted25519\tANY" for name in sorted(ROLES)]
    if actual != expected:
        raise ValueError("Expected exactly four ED25519 accounts with REQUIRE SSL")
    if root_sql("SELECT @@require_secure_transport;\n", tls=True) != "1":
        raise ValueError("Server-wide secure transport is not enabled")
    print("PASS: four database accounts configured for ED25519 and required TLS", flush=True)


def wait_ready(compose):
    for _ in range(90):
        result = subprocess.run(
            [*compose, "exec", "-T", "db", "healthcheck.sh", "--connect", "--innodb_initialized"],
            cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
        )
        if result.returncode == 0:
            return
        time.sleep(2)
    raise ValueError("MariaDB did not become ready; inspect docker compose logs db")


def create_certificate(directory):
    """Create one CA and one local host certificate, with no externally trusted keys."""
    directory.mkdir(mode=0o700)
    previous = os.umask(0o077)
    try:
        run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "365",
            "-subj", "/CN=Hospital Demo CA", "-addext", "basicConstraints=critical,CA:TRUE",
            "-addext", "keyUsage=critical,keyCertSign,cRLSign",
            "-keyout", str(directory / "ca.key"), "-out", str(directory / "ca.pem"))
        run("openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes", "-subj", "/CN=localhost",
            "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1",
            "-keyout", str(directory / "server.key"), "-out", str(directory / "server.csr"))
        run("openssl", "x509", "-req", "-in", str(directory / "server.csr"),
            "-CA", str(directory / "ca.pem"), "-CAkey", str(directory / "ca.key"),
            "-CAcreateserial", "-days", "90", "-sha256", "-copy_extensions", "copy",
            "-out", str(directory / "server.pem"))
    finally:
        os.umask(previous)


def verify(values, with_writes=False):
    port = os.environ.get("HOSPITAL_DB_PORT", "3306")
    cmd = [str(VENV_PYTHON), "app/verify_demo.py", "--ca", "certs/ca.pem", "--port", port]
    if with_writes:
        cmd.append("--write-demo")
    run(*cmd, input_text="".join(f"{values[name]}\n" for name in ROLES))


def setup(values):
    run("docker", "compose", "version")
    run("openssl", "version")
    run(sys.executable, "-m", "venv", ".venv")
    run(str(VENV_PYTHON), "-m", "pip", "install", "-r", "app/requirements.txt")

    env_file = ROOT / ".env"
    if not env_file.exists():
        fd = os.open(env_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as out:
            out.write(f"DB_ROOT_PASSWORD={secrets.token_hex(32)}\n")
    if "DB_ROOT_PASSWORD=change-me" in env_file.read_text().splitlines():
        raise ValueError("Remove the .env placeholder or choose a strong local root password")
    port = os.environ.get("HOSPITAL_DB_PORT", "3306")
    if not port.isascii() or not port.isdecimal() or len(port) > 5 or not 1 <= int(port) <= 65535:
        raise ValueError("HOSPITAL_DB_PORT must be a TCP port between 1 and 65535")
    container = run(*COMPOSE, "ps", "--all", "--quiet", "db", capture=True)
    if container:
        # Do not recreate an existing container with the base (non-TLS) config.
        run(*COMPOSE, "start", "db")
    else:
        run(*COMPOSE, "up", "-d", "--build", "db")
    wait_ready(COMPOSE)
    if not root_sql("SELECT VERSION();\n").startswith(f"{DB_VERSION}-MariaDB"):
        raise ValueError(f"The demo requires MariaDB {DB_VERSION}")
    objects = root_sql(
        "SELECT COUNT(*) FROM information_schema.TABLES "
        "WHERE TABLE_SCHEMA IN ('hospital', 'hospital_audit');\n"
    )
    if objects != "0":
        raise ValueError("Existing hospital objects found; no data was replaced. Use a fresh volume.")

    certificates = ROOT / "certs"
    if not certificates.exists():
        create_certificate(certificates)
    for name in ("ca.pem", "server.pem", "server.key"):
        if not (certificates / name).is_file():
            raise ValueError("Incomplete certs/; move it aside before retrying on a fresh demo")
    run("openssl", "verify", "-CAfile", "certs/ca.pem", "-verify_ip", "127.0.0.1", "certs/server.pem")
    run(*COMPOSE, "exec", "-T", "-u", "root", "db", "mkdir", "-p", TLS_DIR)
    for name in ("ca.pem", "server.pem", "server.key"):
        run(*COMPOSE, "cp", f"certs/{name}", f"db:{TLS_DIR}/")
    run(*COMPOSE, "exec", "-T", "-u", "root", "db", "chown", "-R", "mysql:mysql", TLS_DIR)
    run(*COMPOSE, "exec", "-T", "-u", "root", "db", "chmod", "600", f"{TLS_DIR}/server.key")
    run(*TLS_COMPOSE, "up", "-d", "db")
    wait_ready(TLS_COMPOSE)

    for name in ("hospital_full.sql", "database/02_roles_grants.sql"):
        print(f"Importing {name}", flush=True)
        root_sql((ROOT / name).read_text(encoding="utf-8"), tls=True)
    if root_sql("SELECT COUNT(*) FROM hospital.patients;\n", tls=True) != "200":
        raise ValueError("Unexpected seed data: expected 200 patients")
    root_sql(account_sql(values), tls=True)
    check_accounts()
    verify(values, with_writes=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["setup", "verify"])
    parser.add_argument("--automated", action="store_true", help="generate ephemeral passwords for CI setup")
    args = parser.parse_args()
    if args.automated and args.command != "setup":
        parser.error("--automated requires setup on an empty demo volume")
    try:
        values = passwords(args.automated)
        if args.command == "setup":
            setup(values)
        else:
            check_accounts()
            verify(values)
    except (ValueError, OSError, EOFError, KeyboardInterrupt, getpass.GetPassWarning,
            subprocess.CalledProcessError) as error:
        print(f"Demo {args.command} failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
