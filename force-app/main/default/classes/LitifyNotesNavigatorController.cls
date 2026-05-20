public with sharing class LitifyNotesNavigatorController {
    private static final String NOTE_OBJECT_API_NAME = 'litify_pm__lit_Note__c';
    private static final String TOPIC_FIELD_API_NAME = 'litify_pm__lit_Topic__c';
    private static final String BODY_FIELD_API_NAME = 'litify_pm__lit_Note__c';
    private static final String SORT_CREATED_DATE = 'CreatedDate';
    private static final String SORT_TITLE = 'Name';
    private static final String SORT_TOPIC = 'Topic';
    private static final String SORT_ASC = 'ASC';
    private static final String SORT_DESC = 'DESC';
    private static final Integer MAX_PAGE_SIZE = 50;

    public class NotesRequest {
        @AuraEnabled public Id parentRecordId { get; set; }
        @AuraEnabled public Integer pageSize { get; set; }
        @AuraEnabled public Datetime cursorCreatedDate { get; set; }
        @AuraEnabled public String cursorSortValue { get; set; }
        @AuraEnabled public Id cursorId { get; set; }
        @AuraEnabled public String topic { get; set; }
        @AuraEnabled public Id createdById { get; set; }
        @AuraEnabled public String keyword { get; set; }
        @AuraEnabled public String sortBy { get; set; }
        @AuraEnabled public String sortDirection { get; set; }
    }

    public class NotesResponse {
        @AuraEnabled public List<NoteRow> notes { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }
        @AuraEnabled public Datetime nextCursorCreatedDate { get; set; }
        @AuraEnabled public String nextCursorSortValue { get; set; }
        @AuraEnabled public Id nextCursorId { get; set; }
        @AuraEnabled public String parentObjectApiName { get; set; }
        @AuraEnabled public String lookupFieldApiName { get; set; }
    }

    public class NoteRow {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String topic { get; set; }
        @AuraEnabled public String body { get; set; }
        @AuraEnabled public Id createdById { get; set; }
        @AuraEnabled public String createdByName { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public String recordUrl { get; set; }
    }

    private class SortSpec {
        String sortBy;
        String fieldApiName;
        String direction;
        Boolean isAscending;
    }

    public class FilterOptionsResponse {
        @AuraEnabled public List<PicklistOption> topics { get; set; }
        @AuraEnabled public List<UserOption> createdByUsers { get; set; }
        @AuraEnabled public String parentObjectApiName { get; set; }
        @AuraEnabled public String lookupFieldApiName { get; set; }
    }

    public class PicklistOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class UserOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Id value { get; set; }
        public UserOption(String label, Id value) {
            this.label = label;
            this.value = value;
        }
    }

    @AuraEnabled(cacheable=true)
    public static NotesResponse getNotes(NotesRequest request) {
        validateRequest(request);

        Schema.SObjectType parentType = request.parentRecordId.getSObjectType();
        String parentObjectApiName = parentType.getDescribe().getName();
        String lookupFieldApiName = findNoteLookupField(parentType);
        SortSpec sortSpec = getSortSpec(request);

        Integer requestedSize = request.pageSize == null ? 20 : request.pageSize;
        Integer pageSize = Math.max(1, Math.min(requestedSize, MAX_PAGE_SIZE));
        Integer queryLimit = pageSize + 1;

        Map<String, Object> binds = new Map<String, Object>{
            'parentRecordId' => request.parentRecordId,
            'queryLimit' => queryLimit
        };

        List<String> conditions = new List<String>{ lookupFieldApiName + ' = :parentRecordId' };

        if (String.isNotBlank(request.topic)) {
            conditions.add(TOPIC_FIELD_API_NAME + ' = :topic');
            binds.put('topic', request.topic);
        }
        if (request.createdById != null) {
            conditions.add('CreatedById = :createdById');
            binds.put('createdById', request.createdById);
        }
        if (String.isNotBlank(request.keyword)) {
            String keywordLike = '%' + request.keyword.trim() + '%';
            conditions.add('Name LIKE :keywordLike');
            binds.put('keywordLike', keywordLike);
        }
        addCursorCondition(conditions, binds, request, sortSpec);

        String soql = 'SELECT Id, Name, ' + TOPIC_FIELD_API_NAME + ', ' + BODY_FIELD_API_NAME + ', CreatedById, CreatedBy.Name, CreatedDate ' +
            'FROM ' + NOTE_OBJECT_API_NAME + ' ' +
            'WHERE ' + String.join(conditions, ' AND ') + ' ' +
            'ORDER BY ' + sortSpec.fieldApiName + ' ' + sortSpec.direction + ', Id ' + sortSpec.direction + ' ' +
            'LIMIT :queryLimit';

        List<SObject> queriedRows = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);

        Boolean hasMore = queriedRows.size() > pageSize;
        if (hasMore) {
            queriedRows.remove(queriedRows.size() - 1);
        }

        List<NoteRow> rows = new List<NoteRow>();
        for (SObject sob : queriedRows) {
            rows.add(toNoteRow(sob));
        }

        NotesResponse response = new NotesResponse();
        response.notes = rows;
        response.hasMore = hasMore;
        response.parentObjectApiName = parentObjectApiName;
        response.lookupFieldApiName = lookupFieldApiName;

        if (!rows.isEmpty()) {
            NoteRow lastRow = rows[rows.size() - 1];
            response.nextCursorCreatedDate = lastRow.createdDate;
            response.nextCursorSortValue = getCursorSortValue(lastRow, sortSpec);
            response.nextCursorId = lastRow.id;
        }
        return response;
    }

    @AuraEnabled(cacheable=true)
    public static FilterOptionsResponse getFilterOptions(Id parentRecordId) {
        if (parentRecordId == null) {
            throw new AuraHandledException('parentRecordId is required.');
        }

        Schema.SObjectType parentType = parentRecordId.getSObjectType();
        String lookupFieldApiName = findNoteLookupField(parentType);

        FilterOptionsResponse response = new FilterOptionsResponse();
        response.parentObjectApiName = parentType.getDescribe().getName();
        response.lookupFieldApiName = lookupFieldApiName;
        response.topics = getTopicOptions();
        response.createdByUsers = getCreatedByOptions(lookupFieldApiName, parentRecordId);
        return response;
    }

    private static void validateRequest(NotesRequest request) {
        if (request == null || request.parentRecordId == null) {
            throw new AuraHandledException('parentRecordId is required.');
        }
    }

    private static SortSpec getSortSpec(NotesRequest request) {
        SortSpec sortSpec = new SortSpec();
        sortSpec.sortBy = SORT_CREATED_DATE;
        sortSpec.fieldApiName = SORT_CREATED_DATE;

        if (String.isNotBlank(request.sortBy)) {
            String requestedSortBy = request.sortBy.trim();
            if (requestedSortBy.equalsIgnoreCase(SORT_TITLE) || requestedSortBy.equalsIgnoreCase('Title')) {
                sortSpec.sortBy = SORT_TITLE;
                sortSpec.fieldApiName = SORT_TITLE;
            } else if (requestedSortBy.equalsIgnoreCase(SORT_TOPIC) || requestedSortBy.equalsIgnoreCase(TOPIC_FIELD_API_NAME)) {
                sortSpec.sortBy = SORT_TOPIC;
                sortSpec.fieldApiName = TOPIC_FIELD_API_NAME;
            }
        }

        sortSpec.direction = SORT_DESC;
        if (String.isNotBlank(request.sortDirection) && request.sortDirection.trim().equalsIgnoreCase(SORT_ASC)) {
            sortSpec.direction = SORT_ASC;
        }
        sortSpec.isAscending = sortSpec.direction == SORT_ASC;
        return sortSpec;
    }

    private static void addCursorCondition(
        List<String> conditions,
        Map<String, Object> binds,
        NotesRequest request,
        SortSpec sortSpec
    ) {
        if (request.cursorId == null) {
            return;
        }

        binds.put('cursorId', request.cursorId);
        String comparisonOperator = sortSpec.isAscending ? '>' : '<';

        if (sortSpec.fieldApiName == SORT_CREATED_DATE) {
            if (request.cursorCreatedDate == null) {
                return;
            }

            conditions.add(
                '(CreatedDate ' + comparisonOperator + ' :cursorCreatedDate OR ' +
                '(CreatedDate = :cursorCreatedDate AND Id ' + comparisonOperator + ' :cursorId))'
            );
            binds.put('cursorCreatedDate', request.cursorCreatedDate);
            return;
        }

        if (request.cursorSortValue == null) {
            if (sortSpec.isAscending) {
                conditions.add(
                    '((' + sortSpec.fieldApiName + ' = null AND Id > :cursorId) OR ' +
                    sortSpec.fieldApiName + ' != null)'
                );
            } else {
                conditions.add('(' + sortSpec.fieldApiName + ' = null AND Id < :cursorId)');
            }
            return;
        }

        String cursorCondition =
            '(' + sortSpec.fieldApiName + ' ' + comparisonOperator + ' :cursorSortValue OR ' +
            '(' + sortSpec.fieldApiName + ' = :cursorSortValue AND Id ' + comparisonOperator + ' :cursorId)';
        if (!sortSpec.isAscending) {
            cursorCondition += ' OR ' + sortSpec.fieldApiName + ' = null';
        }
        cursorCondition += ')';
        conditions.add(cursorCondition);
        binds.put('cursorSortValue', request.cursorSortValue);
    }

    private static String getCursorSortValue(NoteRow row, SortSpec sortSpec) {
        if (sortSpec.fieldApiName == SORT_TITLE) {
            return row.title;
        }
        if (sortSpec.fieldApiName == TOPIC_FIELD_API_NAME) {
            return row.topic;
        }
        return null;
    }

    private static String findNoteLookupField(Schema.SObjectType parentType) {
        Schema.SObjectType noteType = Schema.getGlobalDescribe().get(NOTE_OBJECT_API_NAME);
        if (noteType == null) {
            throw new AuraHandledException('Could not find object ' + NOTE_OBJECT_API_NAME + '.');
        }

        String parentObjectApiName = parentType.getDescribe().getName();
        Map<String, Schema.SObjectField> noteFields = noteType.getDescribe().fields.getMap();

        for (String fieldName : noteFields.keySet()) {
            Schema.DescribeFieldResult dfr = noteFields.get(fieldName).getDescribe();
            if (dfr.getType() == Schema.DisplayType.REFERENCE) {
                for (Schema.SObjectType refType : dfr.getReferenceTo()) {
                    if (refType.getDescribe().getName() == parentObjectApiName) {
                        return dfr.getName();
                    }
                }
            }
        }

        throw new AuraHandledException('No lookup field on ' + NOTE_OBJECT_API_NAME + ' references ' + parentObjectApiName + '.');
    }

    private static List<PicklistOption> getTopicOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        Schema.SObjectType noteType = Schema.getGlobalDescribe().get(NOTE_OBJECT_API_NAME);
        Schema.DescribeFieldResult topicField = noteType.getDescribe().fields.getMap().get(TOPIC_FIELD_API_NAME).getDescribe();

        for (Schema.PicklistEntry entry : topicField.getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    private static List<UserOption> getCreatedByOptions(String lookupFieldApiName, Id parentRecordId) {
        Map<String, Object> binds = new Map<String, Object>{ 'parentRecordId' => parentRecordId };
        String soql = 'SELECT CreatedById createdById, CreatedBy.Name createdByName ' +
            'FROM ' + NOTE_OBJECT_API_NAME + ' ' +
            'WHERE ' + lookupFieldApiName + ' = :parentRecordId ' +
            'GROUP BY CreatedById, CreatedBy.Name ' +
            'ORDER BY CreatedBy.Name ASC ' +
            'LIMIT 200';

        List<UserOption> options = new List<UserOption>();
        for (SObject sob : Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)) {
            AggregateResult ar = (AggregateResult) sob;
            options.add(new UserOption((String) ar.get('createdByName'), (Id) ar.get('createdById')));
        }
        return options;
    }

    @TestVisible
    private static NoteRow toNoteRow(SObject sob) {
        NoteRow row = new NoteRow();
        row.id = (Id) sob.get('Id');
        row.title = (String) sob.get('Name');
        row.topic = (String) sob.get(TOPIC_FIELD_API_NAME);
        row.body = (String) sob.get(BODY_FIELD_API_NAME);
        row.createdById = (Id) sob.get('CreatedById');
        row.createdDate = (Datetime) sob.get('CreatedDate');
        row.recordUrl = '/' + String.valueOf(row.id);

        SObject createdBy = sob.getSObject('CreatedBy');
        row.createdByName = createdBy == null ? null : (String) createdBy.get('Name');
        return row;
    }
}
