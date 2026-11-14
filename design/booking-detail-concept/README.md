# Booking Details and Billing concepts

These two Flutter-rendered mockups use the established Emville style and the supplied booking fields. They are design previews only; the production Booking Details and Billing screens are unchanged. The displayed stay and amounts come from the supplied screenshots. Both screens retain the existing fields and actions. Empty F&B and miscellaneous sections are compact.

Regenerate: `flutter test --no-pub --update-goldens --dart-define=CAPTURE_DESIGN=true test/booking_billing_concept_test.dart`.

The same test creates report-letterhead-preview.pdf using illustrative financial rows on two portrait ledger pages. The shared letterhead in lib/ui/emville_pdf_letterhead.dart is wired into the five account reports, work planning and work done reports, and the final booking bill. Only branding changes; report calculations, filtering, exports and receipt data remain unchanged.

Add Bill and Finalise Bill are design-only fixture screens in bill_forms.dart. Finalise remains a modal above Billing and leads to review before saving. Dates are illustrative and keep checkout after check-in.
