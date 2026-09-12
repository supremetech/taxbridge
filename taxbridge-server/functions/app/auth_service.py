"""Register / login / logout. Mỗi account đúng một business (plan BE §3)."""

from google.cloud.firestore_v1.base_query import FieldFilter
from werkzeug.security import check_password_hash, generate_password_hash

from . import errors
from .firestore import db, new_id, new_token, now_iso


def _session_dto(token, account_id, business_id, username, zalo_id):
    return {"token": token, "accountId": account_id, "businessId": business_id,
            "username": username, "zaloId": zalo_id}


def _find_account(username: str):
    docs = list(db.collection("accounts")
                .where(filter=FieldFilter("username", "==", username)).limit(1).stream())
    return docs[0] if docs else None


def _create_session(account: dict) -> dict:
    token = new_token()
    db.collection("sessions").document(token).set({
        "token": token, "accountId": account["accountId"],
        "businessId": account["businessId"], "createdAt": now_iso(), "lastUsedAt": now_iso(),
    })
    return _session_dto(token, account["accountId"], account["businessId"],
                        account["username"], account.get("zaloId"))


def register(username: str, password: str, zalo_id: str | None) -> dict:
    if _find_account(username):
        raise errors.ApiError(409, "USERNAME_TAKEN", "Tên đăng nhập đã tồn tại.")

    zalo_ref, owner_name = None, None
    if zalo_id:
        zalo_ref = db.collection("zalo_users").document(zalo_id)
        zalo = zalo_ref.get()
        if not zalo.exists:
            raise errors.not_found("Zalo user không tồn tại.")
        if zalo.to_dict().get("linkedAccountId"):
            raise errors.ApiError(409, "ZALO_USER_LINKED",
                                  "Zalo user đã liên kết với account khác.")
        # Tên hiển thị Zalo = tên chủ hộ in trên ảnh CK → prompt dùng để đối chiếu (§4.1).
        owner_name = zalo.to_dict().get("displayName")

    account_id, business_id, ts = new_id("acc"), new_id("biz"), now_iso()
    db.collection("businesses").document(business_id).set({
        "businessId": business_id, "name": f"Hộ kinh doanh của {username}",
        "ownerAccountId": account_id, "ownerName": owner_name, "createdAt": ts,
    })
    account = {"accountId": account_id, "username": username,
               "passwordHash": generate_password_hash(password),
               "businessId": business_id, "zaloId": zalo_id, "createdAt": ts}
    db.collection("accounts").document(account_id).set(account)

    if zalo_ref is not None:
        zalo_ref.update({"linkedAccountId": account_id, "linkedBusinessId": business_id})

    return _create_session(account)


def login(username: str, password: str) -> dict:
    doc = _find_account(username)
    if not doc:
        raise errors.unauthorized("Sai tên đăng nhập hoặc mật khẩu.")
    account = doc.to_dict()
    if not check_password_hash(account["passwordHash"], password):
        raise errors.unauthorized("Sai tên đăng nhập hoặc mật khẩu.")
    return _create_session(account)


def logout(token: str) -> None:
    db.collection("sessions").document(token).delete()


def unlinked_zalo_users() -> list[dict]:
    users = [d.to_dict() for d in db.collection("zalo_users").stream()]
    users = [u for u in users if not u.get("linkedAccountId")]
    users.sort(key=lambda u: u.get("lastSeenAt") or "", reverse=True)
    return [{"zaloId": u["zaloId"], "displayName": u.get("displayName"),
             "lastSeenAt": u.get("lastSeenAt")} for u in users]
