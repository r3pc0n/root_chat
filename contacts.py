import json
from pathlib import Path

_CONTACTS_FILE = Path.home() / ".rootchat" / "contacts.json"


def load_contacts() -> list[str]:
    if _CONTACTS_FILE.exists():
        return json.loads(_CONTACTS_FILE.read_text())
    return []


def save_contacts(contacts: list[str]) -> None:
    _CONTACTS_FILE.parent.mkdir(exist_ok=True)
    _CONTACTS_FILE.write_text(json.dumps(contacts))


def add_contact(username: str) -> bool:
    contacts = load_contacts()
    if username in contacts:
        return False
    contacts.append(username)
    save_contacts(contacts)
    return True


def remove_contact(username: str) -> bool:
    contacts = load_contacts()
    if username not in contacts:
        return False
    contacts.remove(username)
    save_contacts(contacts)
    return True
