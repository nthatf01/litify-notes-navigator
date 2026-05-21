@IsTest
private class LitifyNotesNavigatorControllerTest {
    @IsTest
    static void getNotes_requiresParentRecordId() {
        LitifyNotesNavigatorController.NotesRequest request = new LitifyNotesNavigatorController.NotesRequest();

        Test.startTest();
        try {
            LitifyNotesNavigatorController.getNotes(request);
            System.assert(false, 'Expected an AuraHandledException.');
        } catch (AuraHandledException expected) {
            System.assert(true, 'Expected exception thrown.');
        }
        Test.stopTest();
    }

    @IsTest
    static void getNotes_returnsEmptyMatterResponseWithLookupMetadata() {
        LitifyNotesNavigatorController.NotesRequest request = new LitifyNotesNavigatorController.NotesRequest();
        request.parentRecordId = fakeIdFor('litify_pm__Matter__c');
        request.pageSize = 100;

        Test.startTest();
        LitifyNotesNavigatorController.NotesResponse response = LitifyNotesNavigatorController.getNotes(request);
        Test.stopTest();

        System.assertEquals('litify_pm__Matter__c', response.parentObjectApiName);
        System.assertEquals('litify_pm__lit_Matter__c', response.lookupFieldApiName);
        System.assertEquals(false, response.hasMore);
        System.assertEquals(0, response.notes.size());
        System.assertEquals(null, response.nextCursorCreatedDate);
        System.assertEquals(null, response.nextCursorId);
    }

    @IsTest
    static void getNotes_acceptsFiltersAndCursorForIntake() {
        LitifyNotesNavigatorController.NotesRequest request = new LitifyNotesNavigatorController.NotesRequest();
        request.parentRecordId = fakeIdFor('litify_pm__Intake__c');
        request.pageSize = 0;
        request.topic = 'Testing Topic';
        request.createdById = UserInfo.getUserId();
        request.keyword = 'search value';
        request.cursorCreatedDate = System.now();
        request.cursorId = fakeIdFor('litify_pm__lit_Note__c');

        Test.startTest();
        LitifyNotesNavigatorController.NotesResponse response = LitifyNotesNavigatorController.getNotes(request);
        Test.stopTest();

        System.assertEquals('litify_pm__Intake__c', response.parentObjectApiName);
        System.assertEquals('litify_pm__lit_Intake__c', response.lookupFieldApiName);
        System.assertEquals(false, response.hasMore);
        System.assertEquals(0, response.notes.size());
    }

    @IsTest
    static void getNotes_acceptsTitleSortAndCursor() {
        LitifyNotesNavigatorController.NotesRequest request = new LitifyNotesNavigatorController.NotesRequest();
        request.parentRecordId = fakeIdFor('litify_pm__Matter__c');
        request.sortBy = 'Name';
        request.sortDirection = 'asc';
        request.cursorSortValue = 'Earlier Note';
        request.cursorId = fakeIdFor('litify_pm__lit_Note__c');

        Test.startTest();
        LitifyNotesNavigatorController.NotesResponse response = LitifyNotesNavigatorController.getNotes(request);
        Test.stopTest();

        System.assertEquals(false, response.hasMore);
        System.assertEquals(0, response.notes.size());
        System.assertEquals(null, response.nextCursorSortValue);
    }

    @IsTest
    static void getNotes_acceptsTopicSortAndCursor() {
        LitifyNotesNavigatorController.NotesRequest request = new LitifyNotesNavigatorController.NotesRequest();
        request.parentRecordId = fakeIdFor('litify_pm__Matter__c');
        request.sortBy = 'Topic';
        request.sortDirection = 'desc';
        request.cursorSortValue = 'Medical';
        request.cursorId = fakeIdFor('litify_pm__lit_Note__c');

        Test.startTest();
        LitifyNotesNavigatorController.NotesResponse response = LitifyNotesNavigatorController.getNotes(request);
        Test.stopTest();

        System.assertEquals(false, response.hasMore);
        System.assertEquals(0, response.notes.size());
    }

    @IsTest
    static void getNotes_acceptsBlankTopicAscendingCursor() {
        LitifyNotesNavigatorController.NotesRequest request = new LitifyNotesNavigatorController.NotesRequest();
        request.parentRecordId = fakeIdFor('litify_pm__Matter__c');
        request.sortBy = 'Topic';
        request.sortDirection = 'asc';
        request.cursorSortValue = null;
        request.cursorId = fakeIdFor('litify_pm__lit_Note__c');

        Test.startTest();
        LitifyNotesNavigatorController.NotesResponse response = LitifyNotesNavigatorController.getNotes(request);
        Test.stopTest();

        System.assertEquals(false, response.hasMore);
        System.assertEquals(0, response.notes.size());
    }

    @IsTest
    static void getNotes_acceptsNoTopicFilter() {
        LitifyNotesNavigatorController.NotesRequest request = new LitifyNotesNavigatorController.NotesRequest();
        request.parentRecordId = fakeIdFor('litify_pm__Matter__c');
        request.topic = LitifyNotesNavigatorController.NO_TOPIC_OPTION_VALUE;

        Test.startTest();
        LitifyNotesNavigatorController.NotesResponse response = LitifyNotesNavigatorController.getNotes(request);
        Test.stopTest();

        System.assertEquals(false, response.hasMore);
        System.assertEquals(0, response.notes.size());
    }

    @IsTest
    static void getFilterOptions_returnsMatterMetadata() {
        Test.startTest();
        LitifyNotesNavigatorController.FilterOptionsResponse response =
            LitifyNotesNavigatorController.getFilterOptions(fakeIdFor('litify_pm__Matter__c'));
        Test.stopTest();

        System.assertEquals('litify_pm__Matter__c', response.parentObjectApiName);
        System.assertEquals('litify_pm__lit_Matter__c', response.lookupFieldApiName);
        System.assertNotEquals(null, response.topics);
        System.assertNotEquals(null, response.createdByUsers);
    }

    @IsTest
    static void findNoteLookupField_prefersKnownMatterAndIntakeLookups() {
        Test.startTest();
        String matterLookup = LitifyNotesNavigatorController.findNoteLookupField(
            Schema.getGlobalDescribe().get('litify_pm__Matter__c')
        );
        String intakeLookup = LitifyNotesNavigatorController.findNoteLookupField(
            Schema.getGlobalDescribe().get('litify_pm__Intake__c')
        );
        Test.stopTest();

        System.assertEquals('litify_pm__lit_Matter__c', matterLookup);
        System.assertEquals('litify_pm__lit_Intake__c', intakeLookup);
    }

    @IsTest
    static void toNoteRow_mapsFields() {
        SObject note = Schema.getGlobalDescribe().get('litify_pm__lit_Note__c').newSObject();
        note.put('Id', fakeIdFor('litify_pm__lit_Note__c'));
        note.put('Name', 'Test Note');
        note.put('litify_pm__lit_Topic__c', 'Medical');
        note.put('litify_pm__lit_Note__c', '<p>Body</p>');

        LitifyNotesNavigatorController.NoteRow row = LitifyNotesNavigatorController.toNoteRow(note);

        System.assertEquals(note.get('Id'), row.id);
        System.assertEquals('Test Note', row.title);
        System.assertEquals('Medical', row.topic);
        System.assertEquals('<p>Body</p>', row.body);
        System.assertEquals(null, row.createdById);
        System.assertEquals(null, row.createdDate);
        System.assertEquals('/' + String.valueOf(row.id), row.recordUrl);
    }

    private static Id fakeIdFor(String objectApiName) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        System.assertNotEquals(null, objectType, 'Expected object to exist: ' + objectApiName);

        return (Id) (objectType.getDescribe().getKeyPrefix() + '000000000001');
    }
}
