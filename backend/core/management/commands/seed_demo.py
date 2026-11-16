"""Seed a realistic demonstration dataset.

All records are synthetic.  The command is intended for local evaluation and
for exercising the offline client; it must never be run against production.
"""

from datetime import timedelta

from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from catalog.models import Service
from clients.models import Client
from core.models import AppSetting, Counter, Role, SyncSequence, User
from operations.models import (
    Booking,
    FollowUp,
    Incident,
    Placement,
    ReplacementCase,
)
from payments.models import Payment
from workers.models import Worker, WorkerStatusHistory

DEMO_USERS = [
    ("admin", "Admin1234!", Role.ADMIN, "System", "Administrator"),
    ("ops", "Ops1234!", Role.OPERATIONS, "Moses", "Operations"),
    ("verify", "Verify1234!", Role.VERIFICATION, "Rita", "Verifier"),
    ("care", "Care1234!", Role.CUSTOMER_CARE, "Joy", "Customer Care"),
    ("finance", "Finance1234!", Role.FINANCE, "Peter", "Finance"),
    ("readonly", "Read1234!", Role.READONLY, "Grace", "Manager"),
    ("family", "Family1234!", Role.FAMILY, "Daniel", "Ssemakula"),
    ("maid", "Maid1234!", Role.MAID, "Aisha", "Nabirye"),
]


class Command(BaseCommand):
    help = "Create synthetic demo users, workers, clients, bookings and placements."

    def add_arguments(self, parser):
        parser.add_argument(
            "--reset",
            action="store_true",
            help="Hard-delete existing business records before seeding (demo only).",
        )

    @transaction.atomic
    def handle(self, *args, **options):
        if options["reset"]:
            self.stdout.write("Resetting demonstration business records...")
            for model in (
                Payment,
                ReplacementCase,
                FollowUp,
                Incident,
                Placement,
                Booking,
                Client,
                Worker,
                Service,
            ):
                model.objects.all().delete()
            Counter.objects.all().delete()
            SyncSequence.objects.all().delete()

        users = {}
        for username, password, role, first_name, last_name in DEMO_USERS:
            user, created = User.objects.get_or_create(
                username=username,
                defaults={"role": role, "first_name": first_name, "last_name": last_name},
            )
            user.role = role
            user.first_name = first_name
            user.last_name = last_name
            user.is_active = True
            # The owner/administrator also runs the Django administration site;
            # officers keep working in the desktop application.
            user.is_staff = role == Role.ADMIN
            user.is_superuser = role == Role.ADMIN
            if created or password:
                user.set_password(password)
            user.save()
            users[username] = user

        settings_rows = [
            (
                "guarantee_days",
                {"days": 14, "starts_on": "placement_start_date"},
                "Free replacement guarantee length. Exact start/end rule requires owner confirmation.",
                False,
            ),
            (
                "follow_up_window_days",
                {"days": 7},
                "Default interval used when scheduling the next follow-up.",
                False,
            ),
            (
                "pricing_policy",
                {"status": "pending_confirmation"},
                "All prices and package rules must be confirmed by the owner before launch.",
                False,
            ),
            (
                "replacement_policy",
                {"status": "pending_confirmation"},
                "Eligibility and exclusions must be confirmed by the owner before automation.",
                False,
            ),
        ]
        for key, value, description, confirmed in settings_rows:
            AppSetting.objects.update_or_create(
                key=key,
                defaults={"value": value, "description": description, "confirmed": confirmed},
            )

        services = {}
        for name, category, pricing, description in [
            ("Maid / house helper", "MAID", "MONTHLY", "General household support."),
            ("Babysitter / childcare", "BABYSITTER", "MONTHLY", "Childcare and supervision."),
            ("Cleaner", "CLEANER", "ONE_TIME", "Deep or routine cleaning."),
            ("Cook", "COOK", "MONTHLY", "Meal planning and cooking."),
            ("Laundry / ironing", "LAUNDRY", "DAILY", "Laundry and ironing support."),
        ]:
            service, _ = Service.objects.get_or_create(
                name=name,
                defaults={
                    "category": category,
                    "pricing_type": pricing,
                    "description": description,
                    "requirements": "Exact price and package terms pending owner confirmation.",
                    "active": True,
                    "public_visibility": True,
                },
            )
            services[name] = service

        if Worker.objects.exists() and not options["reset"]:
            self.stdout.write(
                self.style.WARNING(
                    "Business records already exist. Use --reset to recreate the demo dataset."
                )
            )
            self._report(users)
            return

        today = timezone.localdate()

        workers = {}
        worker_rows = [
            (
                "Nakato Sarah",
                "0772000101",
                "Ntinda",
                ["General cleaning", "Childcare"],
                ["Luganda", "English"],
                ["Maid / house helper", "Babysitter / childcare"],
                "AVAILABLE",
                "VERIFIED",
                4,
            ),
            (
                "Namusoke Grace",
                "0772000102",
                "Kireka",
                ["Cooking", "Laundry"],
                ["Luganda"],
                ["Cook", "Laundry / ironing"],
                "AVAILABLE",
                "VERIFIED",
                6,
            ),
            (
                "Nabirye Aisha",
                "0772000103",
                "Bweyogerere",
                ["Childcare", "General cleaning"],
                ["Luganda", "English"],
                ["Babysitter / childcare"],
                "PLACED",
                "VERIFIED",
                3,
            ),
            (
                "Akello Brenda",
                "0772000104",
                "Kansanga",
                ["Cleaning"],
                ["Luganda", "Swahili"],
                ["Cleaner"],
                "TRAINING",
                "IN_PROGRESS",
                1,
            ),
            (
                "Kirabo Joan",
                "0772000105",
                "Makindye",
                ["Cooking"],
                ["Luganda"],
                ["Cook"],
                "DOCUMENTS_PENDING",
                "PENDING",
                2,
            ),
            (
                "Nansubuga Esther",
                "0772000106",
                "Najjera",
                ["General cleaning", "Laundry"],
                ["Luganda", "English"],
                ["Maid / house helper", "Laundry / ironing"],
                "AVAILABLE",
                "VERIFIED",
                5,
            ),
        ]
        for index, row in enumerate(worker_rows):
            name, phone, area, skills, languages, categories, status, verification, years = row
            worker = Worker.objects.create(
                full_name=name,
                phone=phone,
                area=area,
                skills=skills,
                languages=languages,
                service_categories=categories,
                status=status,
                verification_status=verification,
                experience_years=years,
                verified_at=timezone.now() if verification == "VERIFIED" else None,
                verified_by_name="Rita Verifier" if verification == "VERIFIED" else "",
                notes="Synthetic demonstration record.",
                user=users["maid"] if index == 2 else None,
            )
            WorkerStatusHistory.objects.create(
                worker=worker,
                from_status="",
                to_status=status,
                changed_by_name="Seed demo",
            )
            workers[name] = worker

        clients = {}
        client_rows = [
            ("Daniel Ssemakula", "0788000201", "Kololo", "PHONE", "family"),
            ("Miriam Nakintu", "0788000202", "Bugolobi", "WHATSAPP", None),
            ("Samuel Okello", "0788000203", "Muyenga", "PHONE", None),
        ]
        for index, (name, phone, area, contact, username) in enumerate(client_rows):
            client = Client.objects.create(
                full_name=name,
                phone=phone,
                area=area,
                preferred_contact=contact,
                notes="Synthetic demonstration record.",
                user=users[username] if username else None,
            )
            clients[name] = client

        def make_booking(client, service, status, days, requirements):
            return Booking.objects.create(
                client=client,
                service=service,
                status=status,
                requested_start_date=today + timedelta(days=days),
                location=client.area,
                schedule="Monday to Saturday",
                requirements=requirements,
                budget_ugx=150000,
                assigned_staff_name="Joy Customer Care",
                created_by_name="Joy Customer Care",
            )

        booking_one = make_booking(
            clients["Daniel Ssemakula"], services["Maid / house helper"], "CONFIRMED", 2,
            "Live-in maid with childcare experience.",
        )
        booking_two = make_booking(
            clients["Samuel Okello"], services["Babysitter / childcare"], "NEW", 5,
            "Care for two children aged 4 and 7.",
        )
        booking_three = make_booking(
            clients["Miriam Nakintu"], services["Cook"], "CONTACTED", 1,
            "Lunch and dinner preparation.",
        )

        placement_one = Placement.objects.create(
            booking=booking_one,
            client=clients["Daniel Ssemakula"],
            worker=workers["Nabirye Aisha"],
            start_date=today - timedelta(days=4),
            status="ACTIVE",
            terms="Monthly placement. Synthetic demonstration terms.",
            responsible_staff_name="Moses Operations",
            client_acknowledgement="Confirmed by phone on the start date.",
        )
        booking_one.status = "CONVERTED"
        booking_one.save()

        placement_two = Placement.objects.create(
            client=clients["Miriam Nakintu"],
            worker=workers["Namusoke Grace"],
            start_date=today - timedelta(days=20),
            status="ACTIVE",
            terms="Monthly placement. Synthetic demonstration terms.",
            responsible_staff_name="Moses Operations",
        )
        placement_three = Placement.objects.create(
            booking=booking_three,
            client=clients["Miriam Nakintu"],
            worker=workers["Nansubuga Esther"],
            start_date=today - timedelta(days=1),
            status="ACTIVE",
            terms="Monthly placement. Synthetic demonstration terms.",
            responsible_staff_name="Moses Operations",
        )
        booking_three.status = "CONVERTED"
        booking_three.save()

        FollowUp.objects.create(
            placement=placement_one,
            due_date=today,
            contact_method="PHONE",
            staff_name="Joy Customer Care",
            created_by_name="Joy Customer Care",
            notes="First check-in after placement.",
        )
        FollowUp.objects.create(
            placement=placement_two,
            due_date=today - timedelta(days=2),
            contact_method="WHATSAPP",
            staff_name="Joy Customer Care",
            created_by_name="Joy Customer Care",
            notes="Overdue demonstration follow-up.",
        )
        FollowUp.objects.create(
            placement=placement_three,
            due_date=today + timedelta(days=3),
            contact_method="PHONE",
            staff_name="Joy Customer Care",
            created_by_name="Joy Customer Care",
        )
        FollowUp.objects.create(
            placement=placement_one,
            due_date=today - timedelta(days=2),
            completed_at=timezone.now() - timedelta(days=2),
            outcome="CLIENT_SATISFIED",
            satisfaction=5,
            contact_method="PHONE",
            staff_name="Joy Customer Care",
            created_by_name="Joy Customer Care",
            notes="Client reported the worker settled in well.",
        )

        ReplacementCase.objects.create(
            placement=placement_two,
            client=placement_two.client,
            original_worker=placement_two.worker,
            problem_category="WORKER_LEFT",
            description="Client reports the worker did not return after the weekend.",
            guarantee_eligible=False,
            eligibility_decision="PENDING",
            status="REVIEWING",
        )
        Incident.objects.create(
            placement=placement_two,
            category="WORKER_LEFT",
            description="Worker did not report for duty on Monday.",
            status="INVESTIGATING",
            reported_by_name="Joy Customer Care",
        )

        Payment.objects.create(
            client=clients["Daniel Ssemakula"],
            placement=placement_one,
            amount_ugx=150000,
            payment_method="MOBILE_MONEY",
            reference="MTN-DEMO-001",
            status="PAID",
            recorded_by_name="Peter Finance",
        )
        Payment.objects.create(
            client=clients["Miriam Nakintu"],
            placement=placement_two,
            amount_ugx=120000,
            payment_method="CASH",
            status="PENDING",
            recorded_by_name="Peter Finance",
        )
        Payment.objects.create(
            client=clients["Samuel Okello"],
            booking=booking_two,
            amount_ugx=150000,
            payment_method="BANK",
            reference="BANK-DEMO-003",
            status="PAID",
            recorded_by_name="Peter Finance",
        )

        self.stdout.write(self.style.SUCCESS("Demo dataset created."))
        self._report(users)

    def _report(self, users):
        self.stdout.write("\nDemo accounts (synthetic data only):")
        for username, password, role, _, _ in DEMO_USERS:
            self.stdout.write(f"  {username:8} / {password:12}  {role}")
