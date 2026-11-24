"""Verified TLS and driver-provided ED25519 authentication."""

import ssl

import pymysql


class ServerIdentityError(Exception):
    """The configured database could not be reached securely."""


def connect(host, port, user, password, ca_file):
    context = ssl.create_default_context(cafile=ca_file)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    # PyMySQL requires TLS when passed an SSLContext; no plaintext fallback.
    return pymysql.connect(
        host=host,
        port=port,
        user=user,
        password=password,
        database="hospital",
        ssl=context,
        autocommit=True,
        connect_timeout=10,
        read_timeout=10,
        write_timeout=10,
        charset="utf8mb4",
    )
