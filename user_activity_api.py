from __future__ import annotations

import logging

from firebase_admin import auth
from flask import Blueprint, jsonify, request

from services.admin_auth import AdminAuthorizationError, verify_admin_authorization, verify_identity
from services.user_activity_service import ActivityRequestError, get_user_activity, record_user_activity

user_activity_api = Blueprint("user_activity_api", __name__)
_logger = logging.getLogger(__name__)


def _response(payload, status=200):
    response = jsonify(payload)
    response.status_code = status
    response.headers["Cache-Control"] = "no-store"
    return response


def _error(code, message, status):
    return _response({"error": {"code": code, "message": message}}, status)


@user_activity_api.errorhandler(AdminAuthorizationError)
def _authorization_error(exc):
    return _error(exc.code, exc.message, exc.status)


def _failure(exc):
    if isinstance(exc, AdminAuthorizationError):
        return _authorization_error(exc)
    if isinstance(exc, ActivityRequestError):
        return _error(exc.code, exc.message, exc.status)
    if isinstance(exc, auth.UserNotFoundError):
        return _error("user_not_found", "This account no longer exists.", 404)
    if isinstance(exc, ValueError):
        return _error("invalid_activity", str(exc), 400)
    _logger.exception("User activity operation failed")
    return _error("activity_unavailable", "User activity could not be loaded or recorded. Please try again.", 503)


@user_activity_api.route("/account/activity", methods=["POST"])
def account_activity():
    identity = verify_identity(request.headers.get("Authorization"))
    try:
        return _response(record_user_activity(identity, request.get_json(silent=True)))
    except Exception as exc:
        return _failure(exc)


@user_activity_api.route("/admin/users/<uid>/activity", methods=["GET"])
def admin_user_activity(uid):
    verify_admin_authorization(request.headers.get("Authorization"))
    try:
        page_size = int(request.args.get("pageSize", "20"))
        if not 1 <= page_size <= 100:
            raise ValueError()
    except ValueError:
        return _error("invalid_page_size", "Page size must be between 1 and 100.", 400)
    try:
        return _response(get_user_activity(uid, page_size=page_size,
                                           page_token=request.args.get("pageToken") or None))
    except Exception as exc:
        return _failure(exc)
