"""Monotonic sequencing helpers used by the sync protocol."""

from django.db import transaction

from core.models import SyncSequence


def next_change_seq() -> int:
    """Reserve the next global change number.

    The single row is locked for the duration of the transaction.  SQLite (used
    by the test suite) serialises writers anyway, so the same code path works on
    both supported engines.
    """
    with transaction.atomic():
        row, _ = SyncSequence.objects.select_for_update().get_or_create(pk=1)
        row.value += 1
        row.save(update_fields=["value"])
        return row.value
