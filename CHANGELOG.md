# Changelog

## 0.1.0

- Initial release. People named in **user-format custom fields** (Tester, Project
  Manager, Code review, Idea owner, Design reviewer) are now notified about the
  issue, which Redmine does not do on its own.
- They stay on the recipient list for as long as they are in the field, so they
  see every change, not only changes to their own field.
- When a field changes, the person **removed** from it is notified as well —
  otherwise a former Tester would never learn the issue moved on without them.
- Applies to every issue custom field of the `user` format, including fields
  created later; there is no list to keep in sync.
- Respects **"No events"** in the user's profile, locked accounts and issue
  visibility. Other notification preferences are deliberately overridden — being
  named as Tester is a direct assignment, and honouring, say, *"only issues I am
  assigned to"* would make the plugin do nothing for a large share of people.
- Honours `redmine_notification_filter` rules for the people it adds, so a user
  who muted status changes stays muted.
- On/off switch in Administration → Plugins; with it off, the plugin adds nobody.
- No migrations, no core changes — `prepend` on `Issue#notified_users` and
  `Journal#notified_users`.
- `extra/selftest.rb`: 7 checks covering issue creation, field change (both the
  new and the removed person), unrelated edits, the kill switch and the
  "No events" preference. Runs in a rolled-back transaction with mail delivery
  redirected to the test collector.
