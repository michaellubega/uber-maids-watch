"""HTTP entry points for the offline sync protocol."""

from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from sync.services import pull_changes, push_mutations


class PullView(APIView):
    permission_classes = [IsAuthenticated]

    @extend_schema(
        parameters=[
            OpenApiParameter("since", int, description="Last change sequence received."),
            OpenApiParameter("limit", int, description="Maximum changes to return (max 1000)."),
        ],
        responses=OpenApiTypes.OBJECT,
    )
    def get(self, request):
        try:
            since = max(0, int(request.query_params.get("since", 0)))
        except (TypeError, ValueError):
            return Response(
                {"since": "Must be a non-negative integer."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            limit = min(max(1, int(request.query_params.get("limit", 500))), 1000)
        except (TypeError, ValueError):
            limit = 500
        return Response(
            pull_changes(user=request.user, since=since, limit=limit, request=request)
        )


class PushView(APIView):
    permission_classes = [IsAuthenticated]

    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request):
        mutations = request.data.get("mutations")
        if not isinstance(mutations, list):
            return Response(
                {"mutations": "An array of mutations is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if len(mutations) > 200:
            return Response(
                {"mutations": "Send at most 200 mutations per request."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        return Response(
            push_mutations(user=request.user, mutations=mutations, request=request)
        )
