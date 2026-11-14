# Flutter visual refresh

The approved Emville direction is implemented in the existing Flutter app. Authentication, reservations, maintenance records, ledger writes, approvals, attachments and report exports retain their existing services and forms.

Implemented: branded startup and sign-in, calendar-first home, persistent primary navigation, Accounts overview with live balances, maintenance overview with existing work planning and task lists, main ledger and petty cash presentation with local type filters and main-ledger search, report navigation, and links to both approval queues. Owner/admin access continues to use the existing role checks; Accounts now receives the shell's role.

Brand assets are bundled locally. Gelasio is distributed with its OFL license in assets/fonts. Shared styling and presentation widgets live in lib/ui.

## Validation

Run `flutter test`, `flutter analyze`, and `flutter build web`. Navigation tests use an isolated HTTP mock and no production credentials or writes. They cover 320px, 390px and 1024px layouts, finance navigation, sign-in presentation, report layouts and transaction interactions. Analysis has 10 pre-existing informational findings outside the reworked screens.

The PNGs in flutter-previews are rendered Flutter screens at 390px using isolated fixture balances and sample reservations and maintenance tasks; they are visual examples, not financial statements. The opt-in design capture test regenerates all nine screens: `flutter test --update-goldens --dart-define=CAPTURE_DESIGN=true test/design_capture_test.dart`. Fixture records live only in test/support/mock_supabase.dart.

Live authentication, OAuth, notification routing and on-device iOS/Android workflows require a device acceptance pass. No database migration, deployment or production transaction was performed.

## Mockup fidelity rework

The HTML files under mockups are the visual reference. The Flutter pages now retain their small uppercase eyebrows, page-name headings, 22px content gutters, 39px row symbols, compact segmented controls, flat bottom navigation, and shared logo/avatar header. The calendar uses the photo-backed welcome banner, live room/arrival/departure totals, compact Monday-first grid, selected-date agenda and primary New booking action. Reports use six cards and a six-month approved-income chart.

The operations views retain live balances and existing receipt, top-up, report and task workflows. The consolidated approval screen supports details, receipts, owner/admin approval, and confirmed deletion, using the existing ledger fields and server permissions. Task completion continues through the existing task workflow.

Captures use a 390 × 844 viewport with real bundled fonts and supplied property photos. Comparison renders are generated from the original HTML and the Flutter captures.

The bottom navigation is consistent across the app: Home / Bookings / Accounts / Property. Home opens the calendar, Bookings opens the reservation list, Accounts opens the finance hub, and Property opens planned maintenance. The hamburger is at the top left on both primary and pushed operations screens and opens the main drawer, including Reports, profile and administration tools.

## Bookings screen

ExistingBookingPage implements the approved bookings.html concept. Keyword searches are case-insensitive and match every value returned from booking_details, including guest names, notes, source enums, reference/ID, amounts and other stored fields. Multiple words must all match somewhere in the record. Results are fetched in stable 500-row pages and searched locally, so typing does not issue additional network requests.

Default Upcoming and Past views cover the next/last 30 days; Enquiries shows enquiry records. A keyword or date filter automatically selects All and removes those default windows. From/To use inclusive calendar-day overlap: check-in day <= To and check-out day >= From. This includes stays spanning the whole filter period and bookings arriving late on the To date. Keyword and date constraints combine with AND. Resetting dates retains the keyword. Selecting a row opens the existing booking details/payment/receipt workflow; New booking retains the existing entry form.

Validated by 19 tests, the opt-in Flutter design capture, and a release web build. The existing advanced search's keyword logic searches guest names and notes only; this page deliberately expands it without applying ILIKE to enum/numeric columns.

## Accounts workflow refresh

The Accounts overview follows accounts-v2 with the same pool photo as the Bookings hero behind the main approved balance. Only database-verified owner/admin roles request or display main balances. Other users see approved petty cash only; main ledger history omits running balances and the main ledger report is role gated. Owner/admin cards place Unapproved balance at bottom right, calculated as ledger minus approved (net pending movement). Role lookup failures deny privileged balance access. These are application protections; existing server policies were not changed.

Income, expense and petty cash receipt forms accept receipts/photos/PDFs and always submit pending, including owner/admin entries. Fund petty cash pre-fills the main expense receiver as Petty cash. It writes one main expense and relies on the existing database link to generate petty income; the client never adds a duplicate top-up. Upload failure reports that the entry was saved without its attachment. Pending queues allow owner/admin review; normal users query their own submissions.

Validated with 29 isolated tests and Flutter screen captures; the analyzer retains its 10 pre-existing informational findings. No production financial records were modified.

## Booking details and billing

The four approved designs are now implemented in BookingDetailsPage, BookingsBillingPage, BookingsAddBillPage and the finalise dialog. Shared booking presentation primitives live in lib/features/bookings/booking_style.dart. Each page keeps the branded header and primary navigation, scrolls its content and pins its primary actions. Extra items use a single page scroll and compact empty states. Currency formatting retains cents and non-INR currency codes.

Existing bookings/extras queries, date requirements, bill confirmation/insert, discount arithmetic, review/proof attachment, pending main-ledger entry, finalised flag and saved PDF workflow are retained. Finalise still opens a modal and requires a separate review before saving. Check-out-before-check-in is rejected, and opening the check-in date picker for a future reservation no longer asserts.

Isolated widget tests cover 320/390/1024 widths, add-bill payload and refreshed totals, cancellation, discount review without writes, invalid checkout dates and money precision. No live booking or financial records were modified.

## Secondary navigation and report selectors

Home, Bookings, Accounts and Property retain the menu button. EmvillePage now displays an actual top-left Back arrow instead of making the logo the back target. Secondary drawer destinations are pushed as routes, so both visible Back and system Back return to the originating tab. Legacy secondary pages retain their native AppBar back buttons.

The five accounting report selectors share report_options_page.dart: ivory background, centered brand header, serif section headings, paper cards, compact forest-green selections, a current-options summary and a fixed Generate report button. Existing monthly, financial-year, custom-date and P&L quarterly choices, status filters, export implementations and main-ledger role guard remain intact. Export controls disable during generation to prevent duplicate exports.
