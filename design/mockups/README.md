# Emville UI concept 01

Open index.html to review startup, login, and calendar-first home mockups. These are a design prototype; Flutter production screens and authentication are unchanged. Calendar month navigation and day selection work locally. All reservations and occupancy values are illustrative.

Logo extracted from the front of Business card.pdf, cropped to pavilion, wordmark, and tagline, with white background removed. Original gold retained.

Selected supplied photographs:
- Startup: 691c326e-34e9-42bb-a6fa-8d743694aac7.JPG — symmetrical veranda, architecture and greenery.
- Login: 07a16904-a26e-4e46-9e38-a88c63a4cc56.JPG — bedroom with river-facing doors.
- Home header: 3cf7fd89-ce77-4532-889f-e677baa04d73.JPG — pool and river.

Flow: brief startup → login when needed → calendar home. Returning authenticated users should proceed directly to the calendar after startup.

## Operations concepts
Open operations.html for six additional screens: Accounts overview, Planned maintenance, Petty cash, Main ledger, Reports, and Approvals. Navigation links connect the screens and return to the original calendar concept. Phone content scrolls with persistent bottom navigation.

Local prototype interactions: ledger type filters and search, petty cash filters, maintenance status filters and completion toggles, sample entry dialogs, approval confirmation, report previews and illustrative CSV downloads. Data is fictional and actions do not call any backend. The Flutter implementation now lives in lib/; these HTML files remain illustrative prototypes. Report layouts are introductory previews, not finished financial statements.

Validated in headless Chrome: filters, search, bill form validation and submission, approval confirmation, CSV download, mobile horizontal fit, and JavaScript errors.
