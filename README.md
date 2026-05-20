# Litify Notes Navigator LWC

Starter Salesforce DX package for an LWC that displays `litify_pm__lit_Note__c` records related to the current record.

## Intended behavior

- Runs on Litify Matter and Intake record pages.
- Dynamically detects which lookup field on `litify_pm__lit_Note__c` references the current record's object type.
- Loads notes newest-first by `CreatedDate`.
- Uses cursor pagination and infinite scroll.
- Displays Topic, Created By, Created Date/Time, Title, and Rich Text Note body.
- Opens note titles in a new browser tab.
- Provides filters for Topic, Created By, and keyword search against `Name`.
- Provides a New button that opens the standard New Note page and prepopulates the detected lookup field.

## Important implementation notes for the coding agent

1. The component is exposed only for `litify_pm__Matter__c` and `litify_pm__Intake__c` in metadata because those are the MVP record pages. The Apex lookup detection is more generic and can support other parent objects if the metadata exposure is expanded.
2. Keyword search is implemented against the Note title (`Name`) only. Salesforce SOQL does not reliably support filtering long/rich text fields like `litify_pm__lit_Note__c` in normal `WHERE ... LIKE` clauses. If full-body search is required, consider SOSL, a searchable summary/plain-text mirror field, or Salesforce Search indexing behavior in the target org.
3. The Apex uses `Database.queryWithBinds(..., AccessLevel.USER_MODE)` and `with sharing` so normal sharing/FLS behavior is respected. Confirm the target org's Apex API version supports this. If not, downgrade to standard dynamic SOQL and add explicit CRUD/FLS checks.
4. The test class is intentionally minimal because Litify managed-package objects often have org-specific required fields. Add org-specific test setup before deployment to production.
5. The New button manually encodes `defaultFieldValues` to avoid an extra dependency. If preferred, replace this helper with Salesforce's `encodeDefaultFieldValues` from `lightning/pageReferenceUtils`.

## Suggested coding-agent checklist

- Verify actual Litify field API names in the org.
- Confirm users can create `litify_pm__lit_Note__c` from the standard New action with only the lookup prepopulated.
- Add production-grade Apex tests using real required fields for Matter/Intake/Note.
- Test on a record with hundreds of Notes.
- Test rich text rendering with links, lists, tables, pasted email content, and images if users paste images into notes.
- Decide whether Topic and Created By filter choices should show all possible values or only values present on the current record's notes.
- Optionally add a Refresh button or subscribe to record changes after a new Note is created.

## File layout

```text
force-app/main/default/classes/
  LitifyNotesNavigatorController.cls
  LitifyNotesNavigatorController.cls-meta.xml
  LitifyNotesNavigatorControllerTest.cls
  LitifyNotesNavigatorControllerTest.cls-meta.xml
force-app/main/default/lwc/litifyNotesNavigator/
  litifyNotesNavigator.html
  litifyNotesNavigator.js
  litifyNotesNavigator.css
  litifyNotesNavigator.js-meta.xml
```
