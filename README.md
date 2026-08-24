# MASH Review Dashboard

A backend-backed Discourse moderator dashboard for permanently reviewing topics and replies.

The plugin renders at the top of `/review`, above the existing Activity Dashboard. The old dashboard can remain installed during migration and testing.

## Features

- Independent review records for topic starters and replies
- Pending, In review, and Reviewed workflows
- Combined chronological feed with filters
- Moderator assignment
- Editable staff-only notes
- Immutable review, assignment, and note-edit audit history
- Automatic capture of new topics and replies
- Optional automatic reopening after content edits
- Topic review status synchronized with the legacy `reviewed` tag
- One-time migration of reviewed-tag topics and their existing replies
- One-time browser import of `mod-dashboard-review-meta`
- Staff-only frontend and API authorization

## Installation

Clone this repository into the Discourse `plugins` directory using the plugin directory name shown below:

```bash
git clone https://github.com/pushpinder6805/Mod-dashboard-3.0.git plugins/Mod-dashboard-3.0
```

For a standard Docker installation, add the clone command to `containers/app.yml` under `hooks.after_code.exec.cmd`, then rebuild the container:

```bash
cd /var/discourse
./launcher rebuild app
```

The rebuild runs the plugin database migrations. Do not remove the old dashboard until the migration and acceptance checks below pass.

## First-run migration

1. Sign in as a moderator or administrator and open `/review`.
2. Confirm that the new **MASH Review Dashboard** appears above the old Activity Dashboard.
3. Review the migration preview and select **Start migration**.
4. Wait for the background job to finish, then refresh the page.
5. On every moderator browser that contains old metadata, select **Import review details**. The browser data is retained; the plugin only adds a separate completion marker after the server confirms the import.
6. Verify legacy reviewed topics, notes, and counts before removing the old dashboard.

The legacy backfill is idempotent. Existing topics carrying the configured `reviewed` tag remain reviewed. When `mash_review_legacy_replies_inherit_reviewed` is enabled, replies that already existed inside those topics receive a clearly marked legacy Reviewed baseline. Every reply created after installation enters Pending independently.

## Settings

- `mash_review_dashboard_enabled`
- `mash_review_reopen_on_edit`
- `mash_review_legacy_replies_inherit_reviewed`
- `mash_review_reviewed_tag`
- `mash_review_items_per_page`

## Acceptance checks

- The new dashboard is shown only to staff and appears above the old dashboard on `/review`.
- A new topic creates one Pending Topic item.
- A new reply creates an independent Pending Reply item.
- Status, assignment, and notes remain after refresh and in another browser.
- Unreview returns an item to Pending without deleting its history or notes.
- Edited reviewed content returns to Pending when the reopen setting is enabled.
- Non-staff users receive no dashboard UI and cannot access plugin endpoints.
- Running the migration or local-storage import twice does not create duplicate items.

## Development verification

From a Discourse development checkout with this repository mounted at `plugins/Mod-dashboard-3.0`:

```bash
bundle exec rake plugin:spec[Mod-dashboard-3.0]
pnpm --dir plugins/Mod-dashboard-3.0 lint
```

## Data ownership

Current status and metadata are stored in plugin-owned PostgreSQL tables:

- `mash_review_items`
- `mash_review_events`
- `mash_review_notes`

`PluginStore` is used only for one-time migration progress markers. Browser local storage is never used as the ongoing source of truth.
