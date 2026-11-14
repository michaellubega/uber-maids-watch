"""Append-only audit logging."""

from core.models import AuditLog


def log_action(
    *,
    actor=None,
    action: str,
    entity: str = "",
    entity_id="",
    metadata: dict | None = None,
    request=None,
) -> AuditLog:
    ip_address = None
    if request is not None:
        forwarded = request.META.get("HTTP_X_FORWARDED_FOR", "")
        ip_address = forwarded.split(",")[0].strip() if forwarded else request.META.get("REMOTE_ADDR")
    return AuditLog.objects.create(
        actor=actor if getattr(actor, "is_authenticated", False) else None,
        actor_name=getattr(actor, "username", "") or "",
        action=action,
        entity=entity,
        entity_id=str(entity_id or ""),
        metadata=metadata or {},
        ip_address=ip_address,
    )
