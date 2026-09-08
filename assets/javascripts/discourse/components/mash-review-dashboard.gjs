import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

const BASE_URL = "/mash-review-dashboard";
const LEGACY_META_KEY = "mod-dashboard-review-meta";
const LEGACY_IMPORTED_KEY = "mash-review-dashboard-meta-imported-v1";

export default class MashReviewDashboard extends Component {
  @service dialog;

  @tracked items = [];
  @tracked
  counts = {
    all: 0,
    pending: 0,
    pending_topics: 0,
    pending_posts: 0,
    in_review: 0,
    reviewed: 0,
  };
  @tracked migration = { status: "not_started" };
  @tracked migrationPreview;
  @tracked loading = true;
  @tracked saving = false;
  @tracked error;
  @tracked status = "pending";
  @tracked targetType = "topic";
  @tracked author = "";
  @tracked tags = "";
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

  get summaryCards() {
    return [
      {
        key: "pending-topics",
        label: "Pending Topics",
        description: "Topics waiting for review",
        count: this.counts.pending_topics,
        status: "pending",
        targetType: "topic",
      },
      {
        key: "pending-posts",
        label: "Pending Posts / Replies",
        description: "Replies waiting for review",
        count: this.counts.pending_posts,
        status: "pending",
        targetType: "post",
      },
      {
        key: "in-review",
        label: "In Review",
        description: "Currently being checked",
        count: this.counts.in_review,
        status: "in_review",
        targetType: "",
      },
      {
        key: "reviewed",
        label: "Reviewed",
        description: "Completed permanent reviews",
        count: this.counts.reviewed,
        status: "reviewed",
        targetType: "",
      },
    ].map((card) => ({
      ...card,
      active:
        this.status === card.status && this.targetType === card.targetType,
    }));
  }

  get currentViewLabel() {
    return (
      this.summaryCards.find((card) => card.active)?.label ||
      "Filtered review items"
    );
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
    if (this.author) {
      query.set("author", this.author);
    }
    if (this.tags.trim()) {
      query.set("tags", this.tags.trim());
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
      this.items = result.items.map((item) => ({
        ...item,
        contentLoading: false,
        editing: false,
        expanded: false,
      }));
      this.counts = result.counts;
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
  selectSummary(card) {
    this.status = card.status;
    this.targetType = card.targetType;
    this.page = 1;
    this.details = null;
    this.load();
  }

  @action
  updateTargetType(event) {
    this.targetType = event.target.value;
  }

  @action
  updateAuthor(event) {
    this.author = event.target.value;
  }

  @action
  updateTags(event) {
    this.tags = event.target.value;
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
    this.author = "";
    this.tags = "";
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

  replaceItem(itemId, changes) {
    this.items = this.items.map((item) =>
      item.id === itemId ? { ...item, ...changes } : item
    );
  }

  async fetchContent(item, expand = true) {
    this.replaceItem(item.id, { contentLoading: true });

    try {
      const result = await ajax(`${BASE_URL}/items/${item.id}/content`);
      this.replaceItem(item.id, {
        ...result.content,
        contentLoading: false,
        expanded: expand,
      });
      return result.content;
    } catch (error) {
      this.replaceItem(item.id, { contentLoading: false });
      popupAjaxError(error);
    }
  }

  @action
  async toggleContent(item) {
    if (item.expanded) {
      this.replaceItem(item.id, { expanded: false });
      return;
    }

    if (item.cooked) {
      this.replaceItem(item.id, { expanded: true });
      return;
    }

    await this.fetchContent(item);
  }

  @action
  async beginEdit(item) {
    let content = item.raw ? item : await this.fetchContent(item);
    if (!content) {
      return;
    }

    this.replaceItem(item.id, {
      editRaw: content.raw,
      editTitle: content.title,
      editing: true,
      expanded: true,
    });
  }

  @action
  updateEditRaw(item, event) {
    this.replaceItem(item.id, { editRaw: event.target.value });
  }

  @action
  updateEditTitle(item, event) {
    this.replaceItem(item.id, { editTitle: event.target.value });
  }

  @action
  cancelEdit(item) {
    this.replaceItem(item.id, { editing: false });
  }

  @action
  async saveEdit(item, event) {
    event.preventDefault();
    if (!item.editRaw?.trim()) {
      return;
    }

    this.saving = true;
    try {
      const result = await ajax(`${BASE_URL}/items/${item.id}/content`, {
        type: "PUT",
        data: {
          raw: item.editRaw,
          original_raw: item.raw,
          title: item.editTitle,
        },
      });
      this.replaceItem(item.id, {
        ...result.item,
        ...result.content,
        editRaw: null,
        editTitle: null,
        editing: false,
        expanded: true,
      });
      if (result.item.status !== item.status) {
        await this.load();
      }
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

  statusLabel(status) {
    return status.replaceAll("_", " ");
  }

  contentTypeLabel(targetType) {
    return targetType === "Post" ? "Post / Reply" : "Topic";
  }

  renderedContent(item) {
    return trustHTML(item.cooked || "");
  }

  <template>
    <section class="mash-review-dashboard" aria-label="MASH Review Dashboard">
      <header class="mash-review-dashboard__header">
        <div>
          <span class="mash-review-dashboard__eyebrow">Moderator workspace</span>
          <h2>Review activity</h2>
          <p>Review topics and replies with permanent, shared staff records.</p>
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
          <div class="mash-review-dashboard__migration-copy">
            <span class="mash-review-dashboard__setup-label">Initial setup</span>
            <strong>Bring your existing reviews into this dashboard</strong>
            {{#if this.migrationPreview}}
              <p>
                {{this.migrationPreview.reviewed_topics}}
                reviewed topics and
                {{this.migrationPreview.reviewed_replies_to_inherit}}
                replies will keep their Reviewed status. This does not delete or
                modify posts.
              </p>
            {{else}}
              <p>
                Run this once after installation to create permanent records for
                existing dashboard content.
              </p>
            {{/if}}
          </div>
          <button
            type="button"
            class="btn btn-primary"
            disabled={{this.saving}}
            {{on "click" this.startBackfill}}
          >
            Migrate existing reviews
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

      <nav class="mash-review-dashboard__summary" aria-label="Review queues">
        {{#each this.summaryCards as |card|}}
          <button
            type="button"
            class="mash-review-summary-card mash-review-summary-card--{{card.key}}
              {{if card.active 'is-active'}}"
            aria-pressed={{card.active}}
            {{on "click" (fn this.selectSummary card)}}
          >
            <span class="mash-review-summary-card__label">{{card.label}}</span>
            <strong>{{card.count}}</strong>
            <span
              class="mash-review-summary-card__description"
            >{{card.description}}</span>
          </button>
        {{/each}}
      </nav>

      <form
        class="mash-review-dashboard__filters"
        {{on "submit" this.applyFilters}}
      >
        <div class="mash-review-dashboard__filters-heading">
          <strong>Filter this queue</strong>
          <span>Narrow results without changing review records.</span>
        </div>
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
          Author
          <input
            type="search"
            value={{this.author}}
            placeholder="Username"
            {{on "input" this.updateAuthor}}
          />
        </label>
        <label>
          Tags
          <input
            type="search"
            value={{this.tags}}
            placeholder="Tag names, separated by commas"
            title="Match any of these topic tags"
            {{on "input" this.updateTags}}
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
        <div class="mash-review-dashboard__results-heading">
          <div>
            <span>Review queue</span>
            <h3>{{this.currentViewLabel}}</h3>
          </div>
          <strong>{{this.pagination.total}} results</strong>
        </div>
        <div class="mash-review-dashboard__list">
          {{#each this.items as |item|}}
            <article class="mash-review-item mash-review-item--{{item.status}}">
              <div class="mash-review-item__content">
                <div class="mash-review-item__eyebrow">
                  <span class="mash-review-item__type">{{this.contentTypeLabel
                      item.target_type
                    }}</span>
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
                {{#if item.editing}}
                  <form
                    class="mash-review-item__editor"
                    {{on "submit" (fn this.saveEdit item)}}
                  >
                    {{#if item.can_edit_title}}
                      <label>
                        Topic title
                        <input
                          type="text"
                          value={{item.editTitle}}
                          {{on "input" (fn this.updateEditTitle item)}}
                        />
                      </label>
                    {{/if}}
                    <label>
                      Content
                      <textarea
                        rows="10"
                        value={{item.editRaw}}
                        {{on "input" (fn this.updateEditRaw item)}}
                      ></textarea>
                    </label>
                    <div class="mash-review-item__editor-actions">
                      <button
                        type="submit"
                        class="btn btn-primary"
                        disabled={{this.saving}}
                      >Save changes</button>
                      <button
                        type="button"
                        class="btn btn-default"
                        disabled={{this.saving}}
                        {{on "click" (fn this.cancelEdit item)}}
                      >Cancel</button>
                    </div>
                  </form>
                {{else}}
                  <div class="mash-review-item__body">
                    {{#if item.expanded}}
                      <div class="mash-review-item__full-content">
                        {{this.renderedContent item}}
                      </div>
                    {{else if item.excerpt}}
                      <p>{{item.excerpt}}</p>
                    {{/if}}
                    {{#if item.content_truncated}}
                      <button
                        type="button"
                        class="btn btn-flat mash-review-item__more-button"
                        disabled={{item.contentLoading}}
                        {{on "click" (fn this.toggleContent item)}}
                      >
                        {{#if item.contentLoading}}
                          Loading…
                        {{else if item.expanded}}
                          Less
                        {{else}}
                          More
                        {{/if}}
                      </button>
                    {{/if}}
                  </div>
                {{/if}}
                <div class="mash-review-item__meta">
                  <span>By @{{item.author.username}}</span>
                  <span>Status:
                    <strong>{{this.statusLabel item.status}}</strong></span>
                  {{#if item.reviewed_by}}<span>Reviewed by @{{item.reviewed_by.username}}</span>{{/if}}
                </div>
              </div>

              <div class="mash-review-item__actions">
                {{#if item.can_edit}}
                  <button
                    type="button"
                    class="btn btn-default"
                    disabled={{this.saving}}
                    {{on "click" (fn this.beginEdit item)}}
                  >
                    Edit
                  </button>
                {{/if}}
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
                <button
                  type="button"
                  class="btn btn-default mash-review-item__details-button"
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
