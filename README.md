# Redmine Notify Field Users

Redmine notifies the author, the assignee and the watchers. Anyone named in a
**user-format custom field** — Tester, Project Manager, Code review, Idea owner,
Design reviewer — gets nothing, even though those are exactly the people who are
supposed to do something about the issue.

This plugin adds them to the recipients.

## What it does

- When an issue is **created**, everyone named in a user-format custom field is
  notified.
- While they stay in the field, they receive e-mails about the issue **like the
  assignee does** — every change, not just changes to their field.
- When the field changes, **the person removed from it is notified too**, so a
  former Tester learns the issue is no longer theirs.
- It applies to **every** issue custom field of the `user` format, including ones
  created later. There is no list to maintain.

## What it respects

- **"No events"** in a user's profile means no e-mail, always.
- Locked accounts and people who cannot see the issue are never notified.
- Other notification preferences (for example *"Only issues I am assigned to"*)
  are deliberately **overridden**: being named as Tester is a direct assignment,
  and if those settings filtered it out, the plugin would silently do nothing for
  a large share of people.
- If `redmine_notification_filter` is installed, its per-user rules apply to the
  people added here as well — a user who asked not to hear about status changes
  will not hear about them from this plugin either.

## Configuration

Administration → Plugins → Notify field users. A single on/off switch; the page
also lists the fields it currently applies to. Nothing else to set up.

## Requirements

- Redmine **5.0+** (developed and tested on **6.1.3**).
- No database migrations. No core changes — `Issue#notified_users` and
  `Journal#notified_users` are extended with `prepend`.

## Why not Restream/notify_custom_users

This replaces [Restream/notify_custom_users](https://github.com/Restream/notify_custom_users),
which does the same job but has not been touched since 2016, declares Redmine 3.3
compatibility and relies on `alias_method_chain` — removed from Rails long ago,
so it cannot load on Redmine 6.

## Testing

```bash
docker compose exec -T --user redmine -e SECRET_KEY_BASE=<key> redmine \
  bin/rails runner -e production plugins/redmine_notify_field_users/extra/selftest.rb
```

Runs entirely inside a transaction that is rolled back, with mail delivery
switched to the test collector — nothing is written and nothing is sent.

## A note on volume

Because people stay on the recipient list for as long as they are in the field,
this increases the number of notification e-mails. Measured against 30 days of
real traffic on the Previo instance: **+43 % recipients**, roughly 230 extra
e-mails a day. If that turns out to be too much, the narrower behaviour — notify
only when the field itself changes — is a small change in
`lib/notify_field_users/issue_patch.rb`.
