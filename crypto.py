from __future__ import annotations

import base64
import json
import os
from dataclasses import dataclass
from hashlib import sha256
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from cryptography.hazmat.primitives.hashes import SHA256
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.serialization import (
    Encoding,
    NoEncryption,
    PrivateFormat,
    PublicFormat,
)

_KEY_FILE = Path.home() / ".rootchat" / "identity.json"
_HKDF_INFO = b"rootchat-v1"


@dataclass
class KeyPair:
    private_bytes: bytes
    public_bytes: bytes


def get_or_create_keypair() -> KeyPair:
    if _KEY_FILE.exists():
        data = json.loads(_KEY_FILE.read_text())
        return KeyPair(
            private_bytes=bytes.fromhex(data["private_key"]),
            public_bytes=bytes.fromhex(data["public_key"]),
        )
    private_key = X25519PrivateKey.generate()
    public_key = private_key.public_key()
    priv = private_key.private_bytes(Encoding.Raw, PrivateFormat.Raw, NoEncryption())
    pub = public_key.public_bytes(Encoding.Raw, PublicFormat.Raw)
    _KEY_FILE.parent.mkdir(exist_ok=True)
    _KEY_FILE.write_text(json.dumps({"private_key": priv.hex(), "public_key": pub.hex()}))
    return KeyPair(private_bytes=priv, public_bytes=pub)


def derive_room_key(password: str, room: str) -> bytes:
    from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
    kdf = PBKDF2HMAC(algorithm=SHA256(), length=32, salt=room.encode(), iterations=100_000)
    return kdf.derive(password.encode())


def fingerprint(pub_bytes: bytes) -> str:
    h = sha256(pub_bytes).hexdigest()[:16]
    return " ".join(h[i : i + 4] for i in range(0, 16, 4))


def _derive_key(raw_shared: bytes) -> bytes:
    return HKDF(algorithm=SHA256(), length=32, salt=None, info=_HKDF_INFO).derive(raw_shared)


async def handshake_host(reader, writer, keypair: KeyPair) -> tuple[bytes, bytes]:
    """Host sends first, then reads. Returns (derived_key, peer_pub_bytes)."""
    writer.write(keypair.public_bytes)
    await writer.drain()
    peer_pub_bytes = await reader.readexactly(32)
    private_key = X25519PrivateKey.from_private_bytes(keypair.private_bytes)
    peer_pub_key = X25519PublicKey.from_public_bytes(peer_pub_bytes)
    return _derive_key(private_key.exchange(peer_pub_key)), peer_pub_bytes


async def handshake_client(reader, writer, keypair: KeyPair) -> tuple[bytes, bytes]:
    """Client reads first, then sends. Returns (derived_key, peer_pub_bytes)."""
    peer_pub_bytes = await reader.readexactly(32)
    writer.write(keypair.public_bytes)
    await writer.drain()
    private_key = X25519PrivateKey.from_private_bytes(keypair.private_bytes)
    peer_pub_key = X25519PublicKey.from_public_bytes(peer_pub_bytes)
    return _derive_key(private_key.exchange(peer_pub_key)), peer_pub_bytes


def encrypt(key: bytes, plaintext: bytes) -> bytes:
    """Encrypt and base64-encode for wire. Caller appends \\n."""
    nonce = os.urandom(12)
    ciphertext = ChaCha20Poly1305(key).encrypt(nonce, plaintext, None)
    return base64.b64encode(nonce + ciphertext)


def decrypt(key: bytes, line: bytes) -> bytes:
    """Base64-decode and decrypt a received line (with or without trailing \\n)."""
    data = base64.b64decode(line.strip())
    return ChaCha20Poly1305(key).decrypt(data[:12], data[12:], None)
