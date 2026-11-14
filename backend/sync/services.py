"""Offline synchronisation protocol.

The Flutter application keeps a full local mirror of the records it is allowed
to see.  Devices pull changes in global change-sequence order and push queued
mutations with an idempotency key and an optimistic-concurrency base version.

Design rules:
* The server is authoritative.  A conflicting device write is rejected and the
  current server record is returned so the user can review the difference.
* Every mutation is processed in its own savepoint, so one bad record cannot
  abort the rest of the batch.
* Mutations are idempotent: replaying the same ``mutation_id`` returns the
  original result instead of applying the change twice.
"""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from typing import Callable

from django.db import IntegrityError, transaction
from django.utils import timezone
from rest_framework import serializers

from catalog.models import Service
from catalog.serializers import ServiceSerializer
from clients.models import Client
from clients.serializers import ClientSerializer
from core.audit import log_action
from core.models import ProcessedMutation, Role, STAFF_ROLES
from operations.models import (
    Booking,
    FollowUp,
    Incident,
    Placement,
    ReplacementCase,
)
from operations.serializers import (
    BookingSerializer,
    FollowUpSerializer,
    IncidentSerializer,
    PlacementSerializer,
    ReplacementCaseSerializer,
)
from payments.models import Payment
from payments.serializers import PaymentSerializer
from workers.models import Worker, WorkerStatusHistory
from workers.serializers import WorkerMinimalSerializer, WorkerSerializer

ALL_STAFF = frozenset(STAFF_ROLES)


def _all(queryset, user):
    return queryset


def _none(queryset, user):
    return queryset.none()


def _scope_worker(queryset, user):
    if user.role == Role.MAID:
        return queryset.filter(user=user)
    if user.role == Role.FAMILY:
        return queryset.filter(placements__client__user=user).distinct()
    if user.role in STAFF_ROLES:
        return queryset
    return queryset.none()


def _scope_client(queryset, user):
    if user.role == Role.FAMILY:
        return queryset.filter(user=user)
    if user.role in STAFF_ROLES:
        return queryset
    return queryset.none()


def _scope_booking(queryset, user):
    if user.role == Role.FAMILY:
        return queryset.filter(client__user=user)
    if user.role in STAFF_ROLES:
        return queryset
    return queryset.none()


def _scope_placement(queryset, user):
    if user.role == Role.FAMILY:
        return queryset.filter(client__user=user)
    if user.role == Role.MAID:
        return queryset.filter(worker__user=user)
    if user.role in STAFF_ROLES:
        return queryset
    return queryset.none()


def _scope_follow_up(queryset, user):
    if user.role == Role.FAMILY:
        return queryset.filter(placement__client__user=user)
    if user.role == Role.MAID:
        return queryset.filter(placement__worker__user=user)
    if user.role in STAFF_ROLES:
        return queryset
    return queryset.none()


def _scope_replacement(queryset, user):
    if user.role == Role.FAMILY:
        return queryset.filter(client__user=user)
    if user.role in STAFF_ROLES:
        return queryset
    return queryset.none()


def _scope_payment(queryset, user):
    if user.role == Role.FAMILY:
        return queryset.filter(client__user=user)
    if user.role in STAFF_ROLES:
        return queryset
    return queryset.none()


def _worker_serializer_for(user):
    return WorkerMinimalSerializer if user.role == Role.FAMILY else WorkerSerializer


@dataclass(frozen=True)
class SyncEntity:
    name: str
    model: type
    serializer: type
    read_roles: frozenset
    write_roles: frozenset
    scope: Callable
    serializer_for_user: Callable | None = None
    after_create: Callable | None = None
    family_may_create: bool = False

    def serializer_for(self, user):
        if self.serializer_for_user:
            return self.serializer_for_user(user)
        return self.serializer


def _booking_after_create(instance, user):
    instance.created_by_name = instance.created_by_name or user.display_name


def _placement_after_create(instance, user):
    if instance.booking:
        instance.booking.status = "CONVERTED"
        instance.booking.save()
    previous_status = instance.worker.status
    instance.worker.status = "PLACED"
    instance.worker.save()
    WorkerStatusHistory.objects.create(
        worker=instance.worker,
        from_status=previous_status,
        to_status="PLACED",
        reason=f"Placed with {instance.client.client_number}.",
        changed_by_name=user.display_name,
    )


def _follow_up_after_create(instance, user):
    if not instance.created_by_name:
        instance.created_by_name = user.display_name
    if not instance.staff_name:
        instance.staff_name = user.display_name


def _incident_after_create(instance, user):
    if not instance.reported_by_name:
        instance.reported_by_name = user.display_name


def _replacement_after_create(instance, user):
    placement = instance.placement
    instance.client = placement.client
    instance.original_worker = placement.worker
    instance.guarantee_eligible = placement.guarantee_status == "IN_GUARANTEE"
    instance.status = "OPEN"


def _payment_after_create(instance, user):
    if not instance.recorded_by_name:
        instance.recorded_by_name = user.display_name


SYNC_ENTITIES: dict[str, SyncEntity] = {
    "service": SyncEntity(
        name="service",
        model=Service,
        serializer=ServiceSerializer,
        read_roles=frozenset(Role.values),
        write_roles=frozenset({Role.ADMIN}),
        scope=_all,
    ),
    "worker": SyncEntity(
        name="worker",
        model=Worker,
        serializer=WorkerSerializer,
        read_roles=frozenset(
            {
                Role.ADMIN,
                Role.OPERATIONS,
                Role.VERIFICATION,
                Role.CUSTOMER_CARE,
                Role.FINANCE,
                Role.READONLY,
                Role.MAID,
                Role.FAMILY,
            }
        ),
        write_roles=frozenset({Role.ADMIN, Role.OPERATIONS, Role.VERIFICATION}),
        scope=_scope_worker,
        serializer_for_user=_worker_serializer_for,
    ),
    "client": SyncEntity(
        name="client",
        model=Client,
        serializer=ClientSerializer,
        read_roles=ALL_STAFF | {Role.FAMILY},
        write_roles=frozenset({Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE}),
        scope=_scope_client,
    ),
    "booking": SyncEntity(
        name="booking",
        model=Booking,
        serializer=BookingSerializer,
        read_roles=frozenset(
            {
                Role.ADMIN,
                Role.OPERATIONS,
                Role.CUSTOMER_CARE,
                Role.FINANCE,
                Role.READONLY,
                Role.FAMILY,
            }
        ),
        write_roles=frozenset(
            {Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE, Role.FAMILY}
        ),
        scope=_scope_booking,
        after_create=_booking_after_create,
        family_may_create=True,
    ),
    "placement": SyncEntity(
        name="placement",
        model=Placement,
        serializer=PlacementSerializer,
        read_roles=ALL_STAFF | {Role.FAMILY, Role.MAID},
        write_roles=frozenset({Role.ADMIN, Role.OPERATIONS}),
        scope=_scope_placement,
        after_create=_placement_after_create,
    ),
    "follow_up": SyncEntity(
        name="follow_up",
        model=FollowUp,
        serializer=FollowUpSerializer,
        read_roles=frozenset(
            {
                Role.ADMIN,
                Role.OPERATIONS,
                Role.CUSTOMER_CARE,
                Role.READONLY,
                Role.FAMILY,
                Role.MAID,
            }
        ),
        write_roles=frozenset({Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE}),
        scope=_scope_follow_up,
        after_create=_follow_up_after_create,
    ),
    "incident": SyncEntity(
        name="incident",
        model=Incident,
        serializer=IncidentSerializer,
        read_roles=frozenset(
            {Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE, Role.READONLY}
        ),
        write_roles=frozenset({Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE}),
        scope=_all,
        after_create=_incident_after_create,
    ),
    "replacement_case": SyncEntity(
        name="replacement_case",
        model=ReplacementCase,
        serializer=ReplacementCaseSerializer,
        read_roles=frozenset(
            {Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE, Role.READONLY, Role.FAMILY}
        ),
        write_roles=frozenset(
            {Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE, Role.FAMILY}
        ),
        scope=_scope_replacement,
        after_create=_replacement_after_create,
        family_may_create=True,
    ),
    "payment": SyncEntity(
        name="payment",
        model=Payment,
        serializer=PaymentSerializer,
        read_roles=frozenset(
            {Role.ADMIN, Role.OPERATIONS, Role.FINANCE, Role.READONLY, Role.FAMILY}
        ),
        write_roles=frozenset({Role.ADMIN, Role.FINANCE}),
        scope=_scope_payment,
        after_create=_payment_after_create,
    ),
}


def serialize_for_pull(entity: SyncEntity, instance, request):
    serializer_class = entity.serializer_for(request.user)
    return serializer_class(instance, context={"request": request}).data


def _json_safe(payload):
    return json.loads(json.dumps(payload, default=str))


def pull_changes(*, user, since: int, limit: int, request):
    """Return changes ordered by the global change sequence."""
    collected: list[tuple[int, str, dict]] = []
    entity_has_more = False

    for entity in SYNC_ENTITIES.values():
        if user.role not in entity.read_roles:
            continue
        queryset = entity.scope(entity.model.objects.all(), user)
        rows = list(
            queryset.filter(change_seq__gt=since).order_by("change_seq")[: limit + 1]
        )
        if len(rows) > limit:
            entity_has_more = True
            rows = rows[:limit]
        for instance in rows:
            collected.append(
                (
                    instance.change_seq,
                    entity.name,
                    serialize_for_pull(entity, instance, request),
                )
            )

    collected.sort(key=lambda item: item[0])
    has_more = entity_has_more or len(collected) > limit
    collected = collected[:limit]

    changes = [
        {
            "entity": entity_name,
            "id": str(data.get("id")),
            "deleted": bool(data.get("deleted_at")),
            "change_seq": change_seq,
            "data": data,
        }
        for change_seq, entity_name, data in collected
    ]
    next_since = collected[-1][0] if collected else since
    return {
        "server_time": timezone.now().isoformat(),
        "since": since,
        "next_since": next_since,
        "has_more": has_more,
        "changes": changes,
    }


def _permission_for(user, entity: SyncEntity, *, creating: bool) -> tuple[bool, str]:
    if user.role in entity.write_roles:
        if user.role == Role.FAMILY and not creating:
            return False, "Clients may create records but cannot edit existing ones."
        return True, ""
    return False, "Your role does not permit this change."


def _find_instance(entity: SyncEntity, record_id):
    return entity.model.objects.filter(pk=record_id).first()


def apply_mutation(*, user, mutation: dict, request):
    """Apply one queued device mutation and return a JSON-safe result."""
    mutation_id = str(mutation.get("mutation_id") or "").strip()
    try:
        uuid.UUID(mutation_id)
    except (ValueError, TypeError):
        return {
            "mutation_id": mutation_id,
            "status": "rejected",
            "errors": {"mutation_id": "A valid mutation UUID is required."},
        }

    existing_result = ProcessedMutation.objects.filter(
        mutation_id=mutation_id, user=user
    ).first()
    if existing_result:
        return {**existing_result.response, "status": "duplicate"}

    entity_name = str(mutation.get("entity") or "").strip()
    entity = SYNC_ENTITIES.get(entity_name)
    if entity is None:
        response = {
            "mutation_id": mutation_id,
            "status": "rejected",
            "errors": {"entity": f"Unknown sync entity '{entity_name}'."},
        }
        return _remember(mutation_id, user, entity_name, uuid.uuid4(), response)

    try:
        record_id = uuid.UUID(str(mutation.get("id")))
    except (ValueError, TypeError):
        response = {
            "mutation_id": mutation_id,
            "status": "rejected",
            "errors": {"id": "A valid record UUID is required."},
        }
        return _remember(mutation_id, user, entity_name, uuid.uuid4(), response)

    operation = str(mutation.get("operation") or "upsert").lower()
    if operation not in {"upsert", "delete"}:
        response = {
            "mutation_id": mutation_id,
            "status": "rejected",
            "errors": {"operation": "Operation must be 'upsert' or 'delete'."},
        }
        return _remember(mutation_id, user, entity_name, record_id, response)

    base_version = mutation.get("base_version")
    try:
        base_version = int(base_version) if base_version is not None else None
    except (TypeError, ValueError):
        base_version = None

    with transaction.atomic():
        instance = _find_instance(entity, record_id)
        creating = instance is None
        allowed, reason = _permission_for(user, entity, creating=creating)
        if not allowed:
            response = {
                "mutation_id": mutation_id,
                "status": "rejected",
                "errors": {"detail": reason},
            }
            return _remember(mutation_id, user, entity_name, record_id, response)

        if instance is not None and user.role not in STAFF_ROLES:
            # Family accounts may only create; never touch an existing row.
            response = {
                "mutation_id": mutation_id,
                "status": "rejected",
                "errors": {"detail": "You cannot edit an existing record."},
            }
            return _remember(mutation_id, user, entity_name, record_id, response)

        if instance is not None and base_version is not None:
            if instance.server_version != base_version:
                response = {
                    "mutation_id": mutation_id,
                    "status": "conflict",
                    "detail": "The record changed on the server while you were offline.",
                    "server_version": instance.server_version,
                    "record": _json_safe(serialize_for_pull(entity, instance, request)),
                }
                return _remember(mutation_id, user, entity_name, record_id, response)

        if operation == "delete":
            if instance is None:
                response = {
                    "mutation_id": mutation_id,
                    "status": "applied",
                    "server_version": 0,
                    "deleted": True,
                }
            else:
                instance.delete()
                log_action(
                    actor=user,
                    action="SYNC_DELETE",
                    entity=f"{entity.model._meta.app_label}.{entity.model.__name__}",
                    entity_id=record_id,
                    metadata={"mutation_id": mutation_id},
                    request=request,
                )
                response = {
                    "mutation_id": mutation_id,
                    "status": "applied",
                    "server_version": instance.server_version,
                    "deleted": True,
                }
            return _remember(mutation_id, user, entity_name, record_id, response)

        data = mutation.get("data") or {}
        if not isinstance(data, dict):
            response = {
                "mutation_id": mutation_id,
                "status": "rejected",
                "errors": {"data": "A record object is required."},
            }
            return _remember(mutation_id, user, entity_name, record_id, response)

        serializer_class = entity.serializer_for(user)
        if instance is None:
            serializer = serializer_class(
                data=data, context={"request": request}
            )
        else:
            serializer = serializer_class(
                instance, data=data, partial=True, context={"request": request}
            )

        if not serializer.is_valid():
            response = {
                "mutation_id": mutation_id,
                "status": "rejected",
                "errors": _json_safe(serializer.errors),
            }
            return _remember(mutation_id, user, entity_name, record_id, response)

        try:
            with transaction.atomic():
                if instance is None:
                    instance = serializer.save(id=record_id)
                    if entity.after_create:
                        entity.after_create(instance, user)
                        instance.save()
                else:
                    instance = serializer.save()
        except (IntegrityError, ValueError) as exc:
            response = {
                "mutation_id": mutation_id,
                "status": "rejected",
                "errors": {"detail": str(exc)},
            }
            return _remember(mutation_id, user, entity_name, record_id, response)

        log_action(
            actor=user,
            action="SYNC_UPSERT",
            entity=f"{entity.model._meta.app_label}.{entity.model.__name__}",
            entity_id=record_id,
            metadata={"mutation_id": mutation_id, "operation": operation},
            request=request,
        )
        response = {
            "mutation_id": mutation_id,
            "status": "applied",
            "server_version": instance.server_version,
            "record": _json_safe(serialize_for_pull(entity, instance, request)),
        }
        return _remember(mutation_id, user, entity_name, record_id, response)


def _remember(mutation_id, user, entity_name, record_id, response):
    response = _json_safe(response)
    try:
        with transaction.atomic():
            ProcessedMutation.objects.create(
                mutation_id=mutation_id,
                user=user,
                entity=entity_name or "unknown",
                record_id=record_id,
                response=response,
            )
    except IntegrityError:
        # A concurrent retry already stored the result.
        existing = ProcessedMutation.objects.filter(mutation_id=mutation_id).first()
        if existing:
            return {**existing.response, "status": "duplicate"}
    return response


def push_mutations(*, user, mutations: list[dict], request):
    results = []
    for mutation in mutations:
        results.append(apply_mutation(user=user, mutation=mutation, request=request))
    applied = sum(1 for row in results if row["status"] in {"applied", "duplicate"})
    return {
        "server_time": timezone.now().isoformat(),
        "received": len(mutations),
        "applied": applied,
        "conflicts": sum(1 for row in results if row["status"] == "conflict"),
        "rejected": sum(1 for row in results if row["status"] == "rejected"),
        "results": results,
    }


__all__ = [
    "SYNC_ENTITIES",
    "apply_mutation",
    "pull_changes",
    "push_mutations",
]
