from flask import g

from .. import auth_service
from . import bp, json_body, required


@bp.post("/register")
def register():
    body = json_body()
    username, password = required(body, "username", "password")
    return auth_service.register(username, password, body.get("zaloId")), 201


@bp.post("/login")
def login():
    body = json_body()
    username, password = required(body, "username", "password")
    return auth_service.login(username, password)


@bp.post("/logout")
def logout():
    auth_service.logout(g.token)
    return "", 204


@bp.get("/zalo-users/unlinked")
def unlinked():
    return auth_service.unlinked_zalo_users()
