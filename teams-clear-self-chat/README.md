# Teams "self-chat" `/clear` — Power Automate flow

Type **`/clear`** in your Teams chat-with-yourself (*Notes* /
[`48:notes`](https://teams.microsoft.com/l/chat/48:notes/conversations?context=%7B%22contextType%22%3A%22chat%22%7D))
and have a Power Automate flow delete every message in that chat.

This folder contains a **fixed, ready-to-import** version of that flow plus a full
write-up of why the previous attempt (`ClearMessageHistory_v6`) failed.

---

## TL;DR — why v6 kept failing the tests

The v6 flow had **two independent, fatal bugs**, either of which fails every run:

| # | v6 did this | Result | Fix |
|---|-------------|--------|-----|
| 1 | `GET …/messages?$filter=deletedDateTime eq null` | **HTTP 400** — `deletedDateTime` is **not** a filterable property. The *List messages in a chat* API only allows `$filter` on `lastModifiedDateTime`/`createdDateTime`, and only when paired with a matching `$orderby`. The **first action failed**, so nothing else ran. | Drop the `$filter`; filter in the flow instead. |
| 2 | `DELETE …/messages/{id}` | **HTTP 405/404** — there is **no `DELETE` on a chat message** in Microsoft Graph. Messages are removed with **`POST …/messages/{id}/softDelete`**. | Use `POST …/softDelete`. |

Two smaller issues were also corrected:

3. **Wrong trigger.** v6 used a **manual "button"** trigger, not the `/clear` keyword
   trigger you wanted (that trigger lives in your `Clear v2` base package — it's
   reused here, unchanged).
4. **Loop could never terminate / mis-counted.** The list endpoint also returns
   **system messages** (`messageType: "systemEventMessage"`) that you cannot delete,
   and soft-deleted messages can linger in the list. The corrected loop accounts for
   both (see [How it works](#how-the-corrected-flow-works)).

Sources: [List messages in a chat](https://learn.microsoft.com/graph/api/chat-list-messages?view=graph-rest-1.0#optional-query-parameters) ·
[chatMessage: softDelete](https://learn.microsoft.com/graph/api/chatmessage-softdelete?view=graph-rest-1.0)

---

## What's in this folder

```
teams-clear-self-chat/
├── ClearSelfChat_KeywordTrigger.zip   ← IMPORT THIS (fires on "/clear")
├── ClearSelfChat_ManualButton.zip     ← fallback (Run button / mobile / scheduled)
├── src/                               ← unzipped, human-readable source of both packages
│   ├── keyword-trigger/…/definition.json
│   └── manual-button/…/definition.json
├── original/                          ← your two uploads, sanitized, for reference/diff
│   ├── v6_ClearMessageHistory_definition.json
│   └── base_Clearv2_definition.json
└── README.md
```

> **Privacy note:** the packages and reference copies here have had your tenant ID,
> user ID, the `shared-teams-…` connection-instance name, and your work email
> **removed**. During import you'll simply select your own Microsoft Teams connection.

---

## How the corrected flow works

Both packages share the same action logic; only the **trigger** differs.

```
TRIGGER
  • Keyword pkg:  "When keywords are mentioned"  →  search "/clear" in chat 48:notes
  • Manual pkg:   "Manually trigger a flow" (Run button)

ACTIONS
  1. Get_My_User_Id        GET  /me?$select=id
  2. Initialize chatId     19:{myId}_{myId}@unq.gbl.spaces   ← the self-chat's Graph id
  3. Initialize nextLink   /me/chats/{chatId}/messages?$top=50
  4. Initialize messageIds []

  5. Collect_All_Message_Ids  (Until nextLink is empty)   ← page through ALL messages
       a. Get_Messages_Page        GET  {nextLink}
       b. Keep_Deletable_Messages  Filter: messageType == 'message' AND deletedDateTime is null
       c. Collect_Page_Ids         For each kept message → Append its id to messageIds
       d. Set_Next_Link            nextLink = @odata.nextLink (or '' to stop)

  6. Delete_Each_Message  (For each id, sequential)
       • Soft_Delete_Message       POST /me/chats/{chatId}/messages/{id}/softDelete
```

### Design decisions (and why)

- **Collect first, then delete.** Deleting while you page can skip or re-loop over
  messages (soft-delete changes `lastModifiedDateTime`, which reshuffles the default
  ordering) and can invalidate the paging cursor you're deleting through. Building the
  full id list first, then deleting, is order-independent and can't loop forever —
  pagination ends when Graph stops returning `@odata.nextLink`.
- **Grow the id list with "Append to array variable", not "Set variable".** Power
  Automate rejects a `Set variable` whose new value references the same variable
  (`Self reference is not supported`), so each page's ids are appended one at a time
  inside a sequential inner `For each`.
- **Filter in the flow, not the URL.** Because `$filter=deletedDateTime eq null` is
  rejected by Graph, the `Keep_Deletable_Messages` step does the equivalent filtering
  client-side and **also drops `systemEventMessage` items** you can't delete.
- **`$top=50`** is the maximum the API allows; smaller pages just mean more loops.
- **Sequential deletes** (`concurrency = 1`) keep you under Graph's chat-write
  throttling limits. Platform default retry handles the occasional `429`.
- **Self-chat id is resolved, not hard-coded.** `48:notes` is a Teams *deep-link*
  alias and is **not** guaranteed to work as a Graph `{chat-id}`. The flow derives the
  documented one-on-one id `19:{myId}_{myId}@unq.gbl.spaces` from `GET /me`. See
  [Troubleshooting](#3-getmessages-returns-404--invalid-chat-id) if your tenant differs.

### Permissions

The Microsoft Teams connector calls Graph with **delegated** permission. Soft-deleting
chat messages needs **`Chat.ReadWrite`** (delegated; *not* supported for personal
Microsoft accounts or application-only). The Teams connector normally already carries
this scope — if a delete returns `403`, see Troubleshooting.

---

## Import & set up

1. Go to **[make.powerautomate.com](https://make.powerautomate.com/)** → **My flows** →
   **Import** → **Import Package (Legacy)**.
2. Upload **`ClearSelfChat_KeywordTrigger.zip`**.
3. Under **Related resources**, set the **Microsoft Teams** action to **Select during
   import** and pick (or create) your Teams connection. Click **Import**.
4. Open the imported flow and confirm the trigger shows **chat = Notes / your
   self-chat**. (If the chat picker is empty, pick your "Notes"/self chat manually, or
   keep the `48:notes` value.) **Save**.
5. Type **`/clear`** in your self-chat to fire it. (Keyword triggers poll, so allow up
   to a minute.)

> Prefer the manual version? Import `ClearSelfChat_ManualButton.zip` instead and run it
> from the **Run** button (web/desktop) or the Power Automate mobile app — handy as a
> reliable fallback while you confirm the keyword trigger behaves in the self-chat.

---

## Test it

1. Post a few throwaway messages in the self-chat (e.g. `test1`, `test2`).
2. Trigger the flow (`/clear` or the Run button).
3. Open the run in Power Automate → every action should be **green**, and
   `Delete_Each_Message` should show one iteration per message.
4. The chat should empty out. (Teams may take a moment to reflect the deletions.)

If a step is red, open it and read the response — the
[Troubleshooting](#troubleshooting) table maps the common ones to fixes.

---

## Troubleshooting

### 1. The flow never fires on `/clear`
The biggest **unknown** here: Teams has documented limits on triggering flows from the
**chat-with-yourself** (e.g. the "For a selected message" action doesn't appear there).
The keyword trigger *usually* works, but if nothing runs:
- Confirm under **My flows → (flow) → Run history** that no run started.
- Make sure the flow lives in your **default environment**.
- Give it ~1 minute (the trigger isn't instant).
- **Fallback:** use `ClearSelfChat_ManualButton.zip` and run it on demand / on a
  [schedule](https://learn.microsoft.com/power-automate/run-scheduled-tasks). The
  delete logic is identical, so this is a fully functional Plan B.

### 2. `Get_My_User_Id` fails (401/403)
The Teams connection isn't authorized. Re-create the connection
(**Data → Connections**) and re-point the action to it.

### 3. `Get_Messages_Page` returns 404 / "invalid chat id"
Your self-chat doesn't use the `19:{myId}_{myId}@unq.gbl.spaces` shape. Find the real id
and hard-code it:
- In [Graph Explorer](https://developer.microsoft.com/graph/graph-explorer) run
  `GET https://graph.microsoft.com/v1.0/me/chats?$expand=members` and find the
  one-on-one chat whose **only member is you** — copy its `id`.
- In the flow, change **`Initialize chatId`** from the expression to that literal id
  (e.g. `19:…@unq.gbl.spaces`). You can also try the literal `48:notes` there.

### 4. A `Soft_Delete_Message` returns 403
Your Teams connector lacks **`Chat.ReadWrite`** consent. Ask an admin to consent, or
test the call in Graph Explorer first (it will prompt for the scope):
`POST /me/chats/{chatId}/messages/{messageId}/softDelete`.

### 5. Some deletes return 429 (throttling)
Expected on very large chats; the platform retries automatically. The loop is already
sequential to minimize this. For thousands of messages, just run it again — already
soft-deleted messages are skipped by the filter.

### 6. Only *some* messages were deleted
`softDelete` only removes messages **you** authored and **non-system** messages. In a
self-chat everything is yours, so the only skips should be system notices, which can't
be removed by users.

---

## Rebuild by hand (if you'd rather not import)

Create an automated cloud flow with the **When keywords are mentioned** trigger
(search `"/clear"`, your self chat), then add the actions exactly as listed in
[How it works](#how-the-corrected-flow-works). Every Graph call uses the Microsoft
Teams connector's **"Send an HTTP request to Teams"** action (operation `HttpRequest`)
with just **URI** + **Method** (+ no body for `softDelete`). The full, annotated
definition is in
[`src/keyword-trigger/…/definition.json`](src/keyword-trigger/Microsoft.Flow/flows/de8e0ae4-ee88-45a4-99ba-0f584a422b30/definition.json).

---

## References

- [List messages in a chat — supported `$filter`/`$orderby`/`$top`](https://learn.microsoft.com/graph/api/chat-list-messages?view=graph-rest-1.0#optional-query-parameters)
- [chatMessage: softDelete — `POST …/softDelete`, `Chat.ReadWrite`](https://learn.microsoft.com/graph/api/chatmessage-softdelete?view=graph-rest-1.0)
- [chatMessage: undoSoftDelete (to recover, within retention)](https://learn.microsoft.com/graph/api/chatmessage-undosoftdelete?view=graph-rest-1.0)
- [chat resource — one-on-one chat id format](https://learn.microsoft.com/graph/api/chat-get?view=graph-rest-1.0#examples)
- [Use flows in Microsoft Teams (triggers incl. "When keywords are mentioned")](https://learn.microsoft.com/power-automate/teams/overview)
