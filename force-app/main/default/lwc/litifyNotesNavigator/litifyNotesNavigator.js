import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import getNotes from '@salesforce/apex/LitifyNotesNavigatorController.getNotes';
import getFilterOptions from '@salesforce/apex/LitifyNotesNavigatorController.getFilterOptions';

const NOTE_OBJECT_API_NAME = 'litify_pm__lit_Note__c';
const DEFAULT_PAGE_SIZE = 20;
const FILTER_DEBOUNCE_MS = 300;
const ALL_OPTION = { label: 'All', value: '' };
const VIEW_EXPANDED = 'expanded';
const VIEW_LIST = 'list';
const SORT_CREATED_DATE = 'CreatedDate';
const SORT_TOPIC = 'Topic';
const SORT_TITLE = 'Name';
const SORT_ASC = 'asc';
const SORT_DESC = 'desc';

export default class LitifyNotesNavigator extends NavigationMixin(LightningElement) {
    @api recordId;
    @api pageSize = DEFAULT_PAGE_SIZE;

    @track notes = [];
    @track topicOptions = [];
    @track createdByOptions = [];

    keyword = '';
    topic = '';
    createdById = '';
    viewMode = VIEW_LIST;
    sortBy = SORT_CREATED_DATE;
    sortDirection = SORT_DESC;

    isLoading = false;
    hasMore = true;
    initialized = false;
    errorMessage;
    nextCursorCreatedDate;
    nextCursorSortValue;
    nextCursorId;
    observer;
    filterDebounce;
    lookupFieldApiName;
    refreshToken = 'initial';

    connectedCallback() {
        this.initialize();
    }

    renderedCallback() {
        this.initializeObserver();
    }

    disconnectedCallback() {
        if (this.observer) {
            this.observer.disconnect();
        }
        window.clearTimeout(this.filterDebounce);
    }

    get topicOptionsWithAll() {
        return [ALL_OPTION, ...this.topicOptions];
    }

    get createdByOptionsWithAll() {
        return [ALL_OPTION, ...this.createdByOptions];
    }

    get showEmptyState() {
        return !this.isLoading && this.notes.length === 0 && !this.errorMessage;
    }

    get showExpandedView() {
        return this.viewMode === VIEW_EXPANDED;
    }

    get showListView() {
        return this.viewMode === VIEW_LIST;
    }

    get viewToggleLabel() {
        return this.showListView ? 'Expanded View' : 'List View';
    }

    get isNewDisabled() {
        return !this.recordId || !this.lookupFieldApiName;
    }

    get isRefreshDisabled() {
        return !this.recordId || this.isLoading;
    }

    get sortIconName() {
        return this.sortDirection === SORT_ASC ? 'utility:arrowup' : 'utility:arrowdown';
    }

    get isCreatedDateSorted() {
        return this.sortBy === SORT_CREATED_DATE;
    }

    get isTopicSorted() {
        return this.sortBy === SORT_TOPIC;
    }

    get isTitleSorted() {
        return this.sortBy === SORT_TITLE;
    }

    get createdDateAriaSort() {
        return this.getAriaSort(SORT_CREATED_DATE);
    }

    get topicAriaSort() {
        return this.getAriaSort(SORT_TOPIC);
    }

    get titleAriaSort() {
        return this.getAriaSort(SORT_TITLE);
    }

    async initialize() {
        if (this.initialized || !this.recordId) {
            return;
        }
        this.initialized = true;

        await Promise.all([
            this.loadFilterOptions(),
            this.loadNotes(true)
        ]);
    }

    async loadFilterOptions() {
        try {
            const result = await getFilterOptions({
                parentRecordId: this.recordId,
                refreshToken: this.refreshToken
            });
            this.lookupFieldApiName = result.lookupFieldApiName;
            this.topicOptions = (result.topics || []).map((item) => ({ label: item.label, value: item.value }));
            this.createdByOptions = (result.createdByUsers || []).map((item) => ({ label: item.label, value: item.value }));
        } catch (error) {
            this.setError(error);
        }
    }

    async loadNotes(reset = false) {
        if (this.isLoading || (!this.hasMore && !reset)) {
            return;
        }

        this.isLoading = true;
        this.errorMessage = undefined;

        if (reset) {
            this.notes = [];
            this.hasMore = true;
            this.nextCursorCreatedDate = undefined;
            this.nextCursorSortValue = undefined;
            this.nextCursorId = undefined;
        }

        try {
            const result = await getNotes({
                request: {
                    parentRecordId: this.recordId,
                    pageSize: Number(this.pageSize) || DEFAULT_PAGE_SIZE,
                    cursorCreatedDate: this.nextCursorCreatedDate,
                    cursorSortValue: this.nextCursorSortValue,
                    cursorId: this.nextCursorId,
                    topic: this.topic || null,
                    createdById: this.createdById || null,
                    keyword: this.keyword || null,
                    sortBy: this.sortBy,
                    sortDirection: this.sortDirection,
                    refreshToken: this.refreshToken
                }
            });

            this.lookupFieldApiName = result.lookupFieldApiName;
            const normalizedNotes = (result.notes || []).map((note) => ({
                ...note,
                topicLabel: note.topic || 'No Topic',
                notePreview: toPlainText(note.body)
            }));

            this.notes = reset ? normalizedNotes : [...this.notes, ...normalizedNotes];
            this.hasMore = result.hasMore;
            this.nextCursorCreatedDate = result.nextCursorCreatedDate;
            this.nextCursorSortValue = result.nextCursorSortValue;
            this.nextCursorId = result.nextCursorId;
        } catch (error) {
            this.setError(error);
        } finally {
            this.isLoading = false;
        }
    }

    initializeObserver() {
        if (this.observer || !this.template.querySelector('[data-id="sentinel"]')) {
            return;
        }

        this.observer = new IntersectionObserver((entries) => {
            if (entries[0].isIntersecting) {
                this.loadNotes(false);
            }
        }, {
            root: null,
            rootMargin: '300px'
        });

        this.observer.observe(this.template.querySelector('[data-id="sentinel"]'));
    }

    handleKeywordChange(event) {
        this.keyword = event.target.value;
        this.debounceReload();
    }

    handleTopicChange(event) {
        this.topic = event.detail.value;
        this.debounceReload();
    }

    handleCreatedByChange(event) {
        this.createdById = event.detail.value;
        this.debounceReload();
    }

    handleClearFilters() {
        this.keyword = '';
        this.topic = '';
        this.createdById = '';
        this.sortBy = SORT_CREATED_DATE;
        this.sortDirection = SORT_DESC;
        this.loadNotes(true);
    }

    handleToggleView() {
        this.viewMode = this.showListView ? VIEW_EXPANDED : VIEW_LIST;
    }

    async handleRefresh() {
        if (this.isRefreshDisabled) {
            return;
        }

        window.clearTimeout(this.filterDebounce);
        this.refreshToken = String(Date.now());
        await Promise.all([
            this.loadFilterOptions(),
            this.loadNotes(true)
        ]);
    }

    handleSort(event) {
        const requestedSortBy = event.currentTarget.dataset.sortBy;
        if (!requestedSortBy) {
            return;
        }

        this.sortDirection =
            this.sortBy === requestedSortBy && this.sortDirection === SORT_ASC
                ? SORT_DESC
                : SORT_ASC;
        this.sortBy = requestedSortBy;
        this.loadNotes(true);
    }

    debounceReload() {
        window.clearTimeout(this.filterDebounce);
        this.filterDebounce = window.setTimeout(() => this.loadNotes(true), FILTER_DEBOUNCE_MS);
    }

    handleNew() {
        if (this.isNewDisabled) {
            this.errorMessage = 'The parent lookup for this record is not ready yet. Try again in a moment.';
            return;
        }

        const defaultFieldValues = encodeDefaultFieldValues({
            [this.lookupFieldApiName]: this.recordId
        });

        const pageReference = {
            type: 'standard__objectPage',
            attributes: {
                objectApiName: NOTE_OBJECT_API_NAME,
                actionName: 'new'
            },
            state: {
                defaultFieldValues,
                nooverride: '1'
            }
        };

        try {
            this[NavigationMixin.Navigate](pageReference);
        } catch (error) {
            this.setError(error);
        }
    }

    handleEdit(event) {
        const recordId = event.currentTarget.dataset.recordId;
        if (!recordId) {
            return;
        }

        const pageReference = {
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: NOTE_OBJECT_API_NAME,
                actionName: 'edit'
            }
        };

        try {
            this[NavigationMixin.Navigate](pageReference);
        } catch (error) {
            this.setError(error);
        }
    }

    setError(error) {
        this.errorMessage = error?.body?.message || error?.message || 'An unexpected error occurred.';
    }

    getAriaSort(columnName) {
        if (this.sortBy !== columnName) {
            return 'none';
        }
        return this.sortDirection === SORT_ASC ? 'ascending' : 'descending';
    }
}

function toPlainText(html) {
    if (!html) {
        return '';
    }

    const container = document.createElement('div');
    container.innerHTML = html;
    return (container.textContent || container.innerText || '').replace(/\s+/g, ' ').trim();
}
