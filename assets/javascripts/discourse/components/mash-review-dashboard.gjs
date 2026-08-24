import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

const BASE_URL = "/mash-review-dashboard";
const LEGACY_META_KEY = "mod-dashboard-review-meta";
const LEGACY_IMPORTED_KEY = "mash-review-dashboard-meta-imported-v1";

export default class MashReviewDashboard extends Component {
  @service dialog;

  @tracked items = [];
  @tracked counts = { all: 0, pending: 0, in_review: 0, reviewed: 0 };
  @tracked staff = [];
  @tracked categories = [];
  @tracked migration = { status: "not_started" };
  @tracked migrationPreview;
  @tracked loading = true;
  @tracked saving = false;
  @tracked error;
  @tracked status = "pending";
  @tracked targetType = "";
  @tracked moderatorId = "";
  @tracked categoryId = "";
  @tracked author = "";
  @tracked dateFrom = "";
  @tracked dateTo = "";
  @tracked page = 1;
  @tracked pagination = { page: 1, total: 0, has_more: false };
  @tracked details;
  @tracked detailsLoading = false;
  @tracked noteDraft = "";
  @tracked localMetadataCount = 0;
  @tracked editingNoteDraft = "";

  constructor() {
    super(...arguments);
    this.localMetadataCount = window.localStorage.getItem(LEGACY_IMPORTED_KEY)
      ? 0
      : Object.keys(this.legacyMetadata).length;
    this.load();
    this.loadMigrationPreview();
  }

  get legacyMetadata() {
    try {
      return JSON.parse(window.localStorage.getItem(LEGACY_META_KEY) || "{}");
    } catch {
      return {};
    }
  }

  get statusTabs() {
    return [
      { key: "pending", label: "Pending", count: this.counts.pending },
      { key: "in_review", label: "In review", count: this.counts.in_review },
      { key: "reviewed", label: "Reviewed", count: this.counts.reviewed },
      { key: "all", label: "All", count: this.counts.all },
    ].map((tab) => ({ ...tab, active: this.status === tab.key }));
  }

  get migrationNeedsAttention() {
    return !["complete", "running", "queued"].includes(this.migration?.status);
  }

  get migrationRunning() {
    return ["running", "queued"].includes(this.migration?.status);
  }

  get hasPreviousPage() {
    return this.page > 1;
  }

  get previousPageDisabled() {
    return !this.hasPreviousPage;
  }

  get nextPageDisabled() {
    return !this.pagination.has_more;
  }

  buildQuery() {
    const query = new URLSearchParams({ page: this.page.toString() });

    if (this.status !== "all") {
      query.set("status", this.status);
    }
    if (this.targetType) {
      query.set("target_type", this.targetType);
    }
    if (this.moderatorId) {
      query.set("moderator_id", this.moderatorId);
    }
    if (this.categoryId) {
      query.set("category_id", this.categoryId);
    }
    if (this.author) {
      query.set("author", this.author);
    }
    if (this.dateFrom) {
      query.set("date_from", this.dateFrom);
    }
    if (this.dateTo) {
      query.set("date_to", this.dateTo);
    }

    return query.toString();
  }

  @action
  async load() {
    this.loading = true;
    this.error = null;

    try {
      const result = await ajax(`${BASE_URL}/items?${this.buildQuery()}`);
      this.items = result.items;
      this.counts = result.counts;
      this.staff = result.staff;
      this.categories = result.categories;
      this.pagination = result.pagination;
      this.migration = result.migration || { status: "not_started" };
    } catch (error) {
      this.error = "The review dashboard could not be loaded.";
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  async loadMigrationPreview() {
    try {
      this.migrationPreview = await ajax(`${BASE_URL}/migration/preview`);
      this.migration = this.migrationPreview.state || this.migration;
    } catch {
      // The main request displays actionable errors. The preview is optional.
    }
  }

  @action
  selectStatus(status) {
    this.status = status;
    this.page = 1;
    this.details = null;
    this.load();
  }

  @action
  updateTargetType(event) {
    this.targetType = event.target.value;
  }

  @action
  updateModerator(event) {
    this.moderatorId = event.target.value;
  }

  @action
  updateCategory(event) {
    this.categoryId = event.target.value;
  }

  @action
  updateAuthor(event) {
    this.author = event.target.value;
  }

  @action
  updateDateFrom(event) {
    this.dateFrom = event.target.value;
  }

  @action
  updateDateTo(event) {
    this.dateTo = event.target.value;
  }

  @action
  applyFilters(event) {
    event.preventDefault();
    this.page = 1;
    this.details = null;
    this.load();
  }

  @action
  clearFilters() {
    this.targetType = "";
    this.moderatorId = "";
    this.categoryId = "";
    this.author = "";
    this.dateFrom = "";
    this.dateTo = "";
    this.page = 1;
    this.load();
  }

  @action
  async changeStatus(item, status) {
    this.saving = true;
    try {
      await ajax(`${BASE_URL}/items/${item.id}/status`, {
        type: "PUT",
        data: { status },
      });
      await this.load();
      if (this.details?.item?.id === item.id) {
        await this.openDetails(item);
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  @action
  async changeAssignment(item, event) {
    const assignedToId = event.target.value;
    if (!assignedToId && !item.assigned_to) {
      return;
    }

    this.saving = true;
    try {
      await ajax(`${BASE_URL}/items/${item.id}/assignment`, {
        type: "PUT",
        data: { assigned_to_id: assignedToId },
      });
      await this.load();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  @action
  async openDetails(item) {
    this.detailsLoading = true;
    try {
      const details = await ajax(`${BASE_URL}/items/${item.id}`);
      details.notes = details.notes.map((note) => ({
        ...note,
        editing: false,
      }));
      this.details = details;
      this.noteDraft = "";
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.detailsLoading = false;
    }
  }

  @action
  closeDetails() {
    this.details = null;
    this.noteDraft = "";
  }

  @action
  updateNoteDraft(event) {
    this.noteDraft = event.target.value;
  }

  @action
  async addNote(event) {
    event.preventDefault();
    const content = this.noteDraft.trim();
    if (!content || !this.details?.item) {
      return;
    }

    this.saving = true;
    try {
      await ajax(`${BASE_URL}/items/${this.details.item.id}/notes`, {
        type: "POST",
        data: { content },
      });
      await this.openDetails(this.details.item);
      await this.load();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  @action
  beginEditNote(note) {
    this.details = {
      ...this.details,
      notes: this.details.notes.map((candidate) => ({
        ...candidate,
        editing: candidate.id === note.id,
      })),
    };
    this.editingNoteDraft = note.content;
  }

  @action
  cancelEditNote() {
    this.details = {
      ...this.details,
      notes: this.details.notes.map((note) => ({ ...note, editing: false })),
    };
    this.editingNoteDraft = "";
  }

  @action
  updateEditingNoteDraft(event) {
    this.editingNoteDraft = event.target.value;
  }

  @action
  async saveNote(note) {
    const content = this.editingNoteDraft.trim();
    if (!content || content === note.content) {
      this.cancelEditNote();
      return;
    }

    this.saving = true;
    try {
      await ajax(`${BASE_URL}/notes/${note.id}`, {
        type: "PUT",
        data: { content },
      });
      await this.openDetails(this.details.item);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  @action
  async performBackfill() {
    this.saving = true;
    try {
      const result = await ajax(`${BASE_URL}/migration/backfill`, {
        type: "POST",
      });
      this.migration = result.state;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  @action
  startBackfill() {
    return this.dialog.confirm({
      message:
        "Create permanent backend review records for all existing topics and replies?",
      didConfirm: () => this.performBackfill(),
    });
  }

  @action
  async performLocalMetadataImport() {
    const records = this.legacyMetadata;
    const count = Object.keys(records).length;
    if (!count) {
      return;
    }

    this.saving = true;
    try {
      const result = await ajax(`${BASE_URL}/migration/local-storage`, {
        type: "POST",
        data: { records },
      });
      this.dialog.alert(
        `Imported ${result.imported} records. ${result.skipped} were skipped.`
      );
      window.localStorage.setItem(
        LEGACY_IMPORTED_KEY,
        new Date().toISOString()
      );
      this.localMetadataCount = 0;
      await this.load();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  @action
  importLocalMetadata() {
    return this.dialog.confirm({
      message: `Import ${this.localMetadataCount} locally stored review records into the backend?`,
      didConfirm: () => this.performLocalMetadataImport(),
    });
  }

  @action
  previousPage() {
    if (!this.hasPreviousPage) {
      return;
    }
    this.page -= 1;
    this.load();
  }

  @action
  nextPage() {
    if (!this.pagination.has_more) {
      return;
    }
    this.page += 1;
    this.load();
  }

  formatDate(value) {
    if (!value) {
      return "Unknown";
    }
    return new Intl.DateTimeFormat(undefined, {
      dateStyle: "medium",
      timeStyle: "short",
    }).format(new Date(value));
  }

  eventLabel(event) {
    return event.action.replaceAll("_", " ");
  }

  <template>
    <section class="mash-review-dashboard" aria-label="MASH Review Dashboard">
      <header class="mash-review-dashboard__header">
        <div>
          <h2>MASH Review Dashboard</h2>
          <p>Permanent staff review records for every topic and reply.</p>
        </div>
        <button
          type="button"
          class="btn btn-default"
          disabled={{this.loading}}
          {{on "click" this.load}}
        >
          Refresh
        </button>
      </header>

      {{#if this.migrationNeedsAttention}}
        <div class="mash-review-dashboard__migration">
          <div>
            <strong>One-time backend migration required</strong>
            {{#if this.migrationPreview}}
              <p>
                {{this.migrationPreview.reviewed_topics}}
                reviewed-tag topics and
                {{this.migrationPreview.reviewed_replies_to_inherit}}
                existing replies will retain Reviewed status.
              </p>
            {{else}}
              <p>Create permanent records for the existing dashboard content.</p>
            {{/if}}
          </div>
          <button
            type="button"
            class="btn btn-primary"
            disabled={{this.saving}}
            {{on "click" this.startBackfill}}
          >
            Start migration
          </button>
        </div>
      {{else if this.migrationRunning}}
        <div
          class="mash-review-dashboard__migration mash-review-dashboard__migration--running"
        >
          <strong>Backend migration is {{this.migration.status}}.</strong>
          <span>Refresh shortly to see the migrated records.</span>
        </div>
      {{/if}}

      {{#if this.localMetadataCount}}
        <div class="mash-review-dashboard__local-import">
          <span>
            This browser contains
            {{this.localMetadataCount}}
            legacy reviewer/comment records.
          </span>
          <button
            type="button"
            class="btn btn-default"
            disabled={{this.saving}}
            {{on "click" this.importLocalMetadata}}
          >
            Import review details
          </button>
        </div>
      {{/if}}

      <nav class="mash-review-dashboard__tabs" aria-label="Review status">
        {{#each this.statusTabs as |tab|}}
          <button
            type="button"
            class="mash-review-dashboard__tab {{if tab.active 'is-active'}}"
            {{on "click" (fn this.selectStatus tab.key)}}
          >
            {{tab.label}}
            <span>{{tab.count}}</span>
          </button>
        {{/each}}
      </nav>

      <form
        class="mash-review-dashboard__filters"
        {{on "submit" this.applyFilters}}
      >
        <label>
          Content
          <select
            value={{this.targetType}}
            {{on "change" this.updateTargetType}}
          >
            <option value="">Topics and replies</option>
            <option value="topic">Topics</option>
            <option value="post">Replies</option>
          </select>
        </label>
        <label>
          Moderator
          <select
            value={{this.moderatorId}}
            {{on "change" this.updateModerator}}
          >
            <option value="">Any moderator</option>
            {{#each this.staff as |moderator|}}
              <option value={{moderator.id}}>{{moderator.username}}</option>
            {{/each}}
          </select>
        </label>
        <label>
          Category
          <select value={{this.categoryId}} {{on "change" this.updateCategory}}>
            <option value="">Any category</option>
            {{#each this.categories as |category|}}
              <option value={{category.id}}>{{category.name}}</option>
            {{/each}}
          </select>
        </label>
        <label>
          Author
          <input
            type="search"
            value={{this.author}}
            placeholder="Username"
            {{on "input" this.updateAuthor}}
          />
        </label>
        <label>
          From
          <input
            type="date"
            value={{this.dateFrom}}
            {{on "input" this.updateDateFrom}}
          />
        </label>
        <label>
          To
          <input
            type="date"
            value={{this.dateTo}}
            {{on "input" this.updateDateTo}}
          />
        </label>
        <div class="mash-review-dashboard__filter-actions">
          <button type="submit" class="btn btn-primary">Apply</button>
          <button
            type="button"
            class="btn btn-default"
            {{on "click" this.clearFilters}}
          >Clear</button>
        </div>
      </form>

      {{#if this.error}}
        <div class="alert alert-error">{{this.error}}</div>
      {{/if}}

      {{#if this.loading}}
        <div class="mash-review-dashboard__empty">Loading review items…</div>
      {{else if this.items.length}}
        <div class="mash-review-dashboard__list">
          {{#each this.items as |item|}}
            <article class="mash-review-item mash-review-item--{{item.status}}">
              <div class="mash-review-item__content">
                <div class="mash-review-item__eyebrow">
                  <span
                    class="mash-review-item__type"
                  >{{item.target_type}}</span>
                  {{#if item.category}}<span
                    >{{item.category.name}}</span>{{/if}}
                  <span>{{this.formatDate item.content_created_at}}</span>
                  {{#if item.legacy}}<span
                      class="mash-review-item__legacy"
                    >Legacy</span>{{/if}}
                </div>
                <a
                  class="mash-review-item__title"
                  href={{item.url}}
                >{{item.title}}</a>
                {{#if item.excerpt}}<p>{{item.excerpt}}</p>{{/if}}
                <div class="mash-review-item__meta">
                  <span>By @{{item.author.username}}</span>
                  <span>Status: <strong>{{item.status}}</strong></span>
                  {{#if item.assigned_to}}<span>Assigned to @{{item.assigned_to.username}}</span>{{/if}}
                  {{#if item.reviewed_by}}<span>Reviewed by @{{item.reviewed_by.username}}</span>{{/if}}
                </div>
              </div>

              <div class="mash-review-item__actions">
                {{#if item.is_pending}}
                  <button
                    type="button"
                    class="btn btn-default"
                    disabled={{this.saving}}
                    {{on "click" (fn this.changeStatus item "in_review")}}
                  >
                    Start review
                  </button>
                {{/if}}
                {{#if item.is_reviewed}}
                  <button
                    type="button"
                    class="btn btn-default"
                    disabled={{this.saving}}
                    {{on "click" (fn this.changeStatus item "pending")}}
                  >
                    Unreview
                  </button>
                {{else}}
                  <button
                    type="button"
                    class="btn btn-primary"
                    disabled={{this.saving}}
                    {{on "click" (fn this.changeStatus item "reviewed")}}
                  >
                    Mark reviewed
                  </button>
                {{/if}}
                <label class="mash-review-item__assignment">
                  <span>Assign</span>
                  <select
                    disabled={{this.saving}}
                    {{on "change" (fn this.changeAssignment item)}}
                  >
                    <option value="">{{if
                        item.assigned_to
                        "Unassign"
                        "Choose moderator"
                      }}</option>
                    {{#each this.staff as |moderator|}}
                      <option
                        value={{moderator.id}}
                      >{{moderator.username}}</option>
                    {{/each}}
                  </select>
                </label>
                <button
                  type="button"
                  class="btn btn-default"
                  {{on "click" (fn this.openDetails item)}}
                >
                  Notes & history ({{item.notes_count}})
                </button>
              </div>
            </article>
          {{/each}}
        </div>

        <div class="mash-review-dashboard__pagination">
          <button
            type="button"
            class="btn btn-default"
            disabled={{this.previousPageDisabled}}
            {{on "click" this.previousPage}}
          >
            Previous
          </button>
          <span>Page
            {{this.pagination.page}}
            ·
            {{this.pagination.total}}
            items</span>
          <button
            type="button"
            class="btn btn-default"
            disabled={{this.nextPageDisabled}}
            {{on "click" this.nextPage}}
          >
            Next
          </button>
        </div>
      {{else}}
        <div class="mash-review-dashboard__empty">No review items match these
          filters.</div>
      {{/if}}

      {{#if this.detailsLoading}}
        <div class="mash-review-dashboard__details">Loading notes and history…</div>
      {{else if this.details}}
        <aside class="mash-review-dashboard__details">
          <header>
            <div>
              <span>Staff-only details</span>
              <h3>{{this.details.item.title}}</h3>
            </div>
            <button
              type="button"
              class="btn btn-flat"
              {{on "click" this.closeDetails}}
            >Close</button>
          </header>

          <form
            class="mash-review-dashboard__note-form"
            {{on "submit" this.addNote}}
          >
            <label for="mash-review-note">Add an internal moderator note</label>
            <textarea
              id="mash-review-note"
              value={{this.noteDraft}}
              rows="3"
              {{on "input" this.updateNoteDraft}}
            ></textarea>
            <button
              type="submit"
              class="btn btn-primary"
              disabled={{this.saving}}
            >Add note</button>
          </form>

          <section>
            <h4>Internal notes</h4>
            {{#each this.details.notes as |note|}}
              <article class="mash-review-note">
                {{#if note.editing}}
                  <textarea
                    value={{this.editingNoteDraft}}
                    rows="3"
                    {{on "input" this.updateEditingNoteDraft}}
                  ></textarea>
                  <footer>
                    <button
                      type="button"
                      class="btn btn-primary btn-small"
                      {{on "click" (fn this.saveNote note)}}
                    >Save</button>
                    <button
                      type="button"
                      class="btn btn-default btn-small"
                      {{on "click" this.cancelEditNote}}
                    >Cancel</button>
                  </footer>
                {{else}}
                  <p>{{note.content}}</p>
                  <footer>
                    @{{note.created_by.username}}
                    ·
                    {{this.formatDate note.created_at}}
                    <button
                      type="button"
                      class="btn btn-small"
                      {{on "click" (fn this.beginEditNote note)}}
                    >Edit</button>
                  </footer>
                {{/if}}
              </article>
            {{else}}
              <p>No internal notes yet.</p>
            {{/each}}
          </section>

          <section>
            <h4>Audit history</h4>
            <ol class="mash-review-history">
              {{#each this.details.events as |event|}}
                <li>
                  <strong>{{this.eventLabel event}}</strong>
                  {{#if event.actor}} by @{{event.actor.username}}{{/if}}
                  ·
                  {{this.formatDate event.created_at}}
                  {{#if event.reason}}<div>{{event.reason}}</div>{{/if}}
                </li>
              {{else}}
                <li>No recorded events.</li>
              {{/each}}
            </ol>
          </section>
        </aside>
      {{/if}}
    </section>
  </template>
}
