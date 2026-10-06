"""Authenticated editors for already imported topic languages and Bible text."""
from __future__ import annotations

import json
import logging
import re
from functools import wraps

from flask import Blueprint, current_app, request

from services.admin_auth import AdminAuthorizationError, verify_admin_authorization
from services.admin_content_service import AdminContentRepository, ContentConflictError, ContentNotFoundError

admin_content_api = Blueprint("admin_content_api", __name__)
_logger = logging.getLogger(__name__)


def _response(payload, status=200):
    response = current_app.response_class(json.dumps(payload, ensure_ascii=False, default=str),
                                          status=status, content_type="application/json; charset=utf-8")
    response.headers["Cache-Control"] = "no-store"
    return response


def _error(code, message, status):
    return _response({"error": {"code": code, "message": message}}, status)


def _endpoint(function):
    @wraps(function)
    def authenticated(**kwargs):
        try:
            admin = verify_admin_authorization(request.headers.get("Authorization"))
            language = kwargs.get("language", "")
            if not re.fullmatch(r"[a-z][a-z0-9_-]{1,79}", language):
                raise ValueError("Language identifier is invalid.")
            for field in ("version", "book"):
                if field in kwargs:
                    value = kwargs[field]
                    if not value.strip() or len(value) > 160 or any(ord(c) < 32 for c in value) or value in {".", ".."}:
                        raise ValueError(f"{field.title()} identifier is invalid.")
            if "chapter" in kwargs and not re.fullmatch(r"[1-9][0-9]{0,2}", kwargs["chapter"]):
                raise ValueError("Chapter must be a positive number.")
            return function(admin=admin, **kwargs)
        except AdminAuthorizationError as exc:
            return _error(exc.code, exc.message, exc.status)
        except ContentConflictError as exc:
            return _error("content_conflict", str(exc), 409)
        except ContentNotFoundError as exc:
            return _error("content_not_found", str(exc), 404)
        except ValueError as exc:
            return _error("invalid_content", str(exc), 400)
        except Exception:
            _logger.exception("Admin content operation failed")
            return _error("content_save_failed" if request.method == "POST" else "content_load_failed",
                          "Content could not be saved. Reload and try again." if request.method == "POST" else "Content could not be loaded. Try again.", 500)
    return authenticated


def _payload(allowed):
    value = request.get_json(silent=True)
    if not isinstance(value, dict) or set(value) - set(allowed):
        raise ValueError("Provide a JSON object containing only the editor's supported fields.")
    return value


@admin_content_api.route("/admin/content/topics/<language>", methods=["GET", "POST"])
@_endpoint
def topics(language, admin):
    repository = AdminContentRepository()
    if request.method == "POST":
        return _response(repository.save_topics(language, _payload({"revision", "metadata", "topics"}), admin["uid"]))
    return _response(repository.topics(language))


@admin_content_api.route("/admin/content/bibles/<language>/<version>", methods=["GET", "POST"])
@_endpoint
def bible(language, version, admin):
    repository = AdminContentRepository()
    if request.method == "POST":
        return _response(repository.save_bible(language, version, _payload({"revision", "metadata"}), admin["uid"]))
    return _response(repository.bible(language, version))


@admin_content_api.route("/admin/content/bibles/<language>/<version>/<book>/<chapter>", methods=["GET", "POST"])
@_endpoint
def chapter(language, version, book, chapter, admin):
    repository = AdminContentRepository()
    if request.method == "POST":
        return _response(repository.save_chapter(language, version, book, chapter,
                                                  _payload({"revision", "verses"}), admin["uid"]))
    return _response(repository.chapter(language, version, book, chapter))
