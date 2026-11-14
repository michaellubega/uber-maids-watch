"""Private file storage for identity documents and worker photos.

Files are written outside the public media tree.  There is deliberately no
public URL: access always goes through an authorised API view that writes an
audit event.
"""

from django.conf import settings
from django.core.files.storage import FileSystemStorage


class PrivateDocumentStorage(FileSystemStorage):
    """Filesystem storage rooted at ``settings.PRIVATE_MEDIA_ROOT``.

    The location is resolved at runtime instead of being baked into migrations,
    so the same migration set works on a developer laptop, a container and a
    Windows installation.
    """

    def __init__(self) -> None:
        super().__init__(location=None, base_url=None)

    @property
    def base_location(self):
        return settings.PRIVATE_MEDIA_ROOT

    def deconstruct(self):
        return ("core.storage.PrivateDocumentStorage", [], {})


private_storage = PrivateDocumentStorage()
