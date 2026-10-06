from __future__ import annotations

import logging

from firebase_admin import auth, exceptions
from flask import Blueprint, jsonify, request

from services.admin_auth import AdminAuthorizationError, verify_admin_authorization, verify_identity
from services.admin_user_service import get_admin_user, list_admin_users, update_admin_user
from services.membership_service import MembershipConflictError, get_account_access

admin_users_api = Blueprint("admin_users_api", __name__)
_logger = logging.getLogger(__name__)


def _response(payload, status=200):
    response = jsonify(payload)
    response.status_code = status
    response.headers["Cache-Control"] = "no-store"
    return response


def _error(code, message, status):
    return _response({"error": {"code": code, "message": message}}, status)


@admin_users_api.errorhandler(AdminAuthorizationError)
def _authorization_error(exc):
    return _error(exc.code, exc.message, exc.status)


def _failure(exc):
    if isinstance(exc, MembershipConflictError):
        return _error("membership_conflict", str(exc), 409)
    if isinstance(exc, auth.UserNotFoundError):
        return _error("user_not_found", "This account no longer exists.", 404)
    if isinstance(exc, (ValueError, exceptions.InvalidArgumentError)):
        return _error("invalid_user_access", str(exc) if isinstance(exc, ValueError) else "Invalid account request.", 400)
    _logger.exception("Account access operation failed")
    return _error("user_directory_unavailable", "Account access could not be loaded or saved. Please try again.", 503)


@admin_users_api.route("/account/access", methods=["GET"])
def account_access():
    identity = verify_identity(request.headers.get("Authorization"))
    try:
        return _response(get_account_access(identity))
    except AdminAuthorizationError:
        raise
    except Exception as exc:
        return _failure(exc)


@admin_users_api.route("/admin/users", methods=["GET"])
def admin_users():
    admin = verify_admin_authorization(request.headers.get("Authorization"))
    try:
        page_size = int(request.args.get("pageSize", "50"))
        if not 1 <= page_size <= 100:
            raise ValueError()
    except ValueError:
        return _error("invalid_page_size", "Page size must be between 1 and 100.", 400)
    try:
        return _response(list_admin_users(page_size=page_size, page_token=request.args.get("pageToken") or None,
                                          current_user_uid=admin["uid"]))
    except Exception as exc:
        return _failure(exc)


@admin_users_api.route("/admin/users/<uid>", methods=["GET", "POST"])
def admin_user(uid):
    admin = verify_admin_authorization(request.headers.get("Authorization"))
    try:
        if request.method == "POST":
            user = update_admin_user(uid, request.get_json(silent=True), actor=admin)
        else:
            user = get_admin_user(uid, current_user_uid=admin["uid"])
        return _response({"user": user})
    except AdminAuthorizationError:
        raise
    except Exception as exc:
        return _failure(exc)
