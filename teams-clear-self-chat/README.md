# Teams "self-chat" cleaner — Power Automate flow

A Power Automate flow that **deletes every message in your Teams chat-with-yourself**
(*Notes* /
[`48:notes`](https://teams.microsoft.com/l/chat/48:notes/conversations?context=%7B%22contextType%22%3A%22chat%22%7D)),
triggered by a **Run button** (web / desktop / mobile app).

> **Why a button and not a typed `/clear` command?** We tried hard to make a typed
> keyword (`/clear`, then `clearchat`) trigger this. It can't work for the self-chat:
> Teams will *create* the keyword subscription but never *delivers* the trigger for the
> chat-with-yourself. Full story in [Appendix A](#appendix-a-why-not-a-typed-command).

---

## What's in this folder

```
teams-clear-self-chat/
├── ClearSelfChat_ManualButton.zip     ← IMPORT THIS
├── src/manual-button/…/definition.json   ← unzipped, readable source
├── original/                          ← your two original uploads, sanitized, for diff
│   ├── v6_ClearMessageHistory_definition.json
│   └── base_Clearv2_definition.json
└── README.md
```

> **Privacy note:** every committed file (and the zip) has had your tenant ID, user ID,
> the `shared-teams-…` connection-instance name, and your work email **removed**. You
> select your own Microsoft Teams connection during import; the self-chat ID defaults to
> the `48:notes` alias and is editable in one field.

---

## Import & run

1. **[make.powerautomate.com](https://make.powerautomate.com/)** → **My flows** →
   **Import** → **Import Package (Legacy)**.
2. Upload **`ClearSelfChat_ManualButton.zip`**.
3. Under **Related resources**, set the **Microsoft Teams** action to **Select during
   import** and pick (or create) your Teams connection → **Import**.
4. Open the flow → **Save**.
5. Run it: the **Run** button in the designer, **My flows → Run**, or the **Power
   Automate mobile app** (handy from your phone). It takes no inputs.

**First, a 20-second pre-check** so the very first run works — see
[Confirm your self-chat ID](#confirm-your-self-chat-id) below.

---

## How it works

```
TRIGGER  "Manually trigger a flow" (Run button) — no inputs

ACTIONS
  1. Initialize chatId     "48:notes"   ← your self-chat (editable; see pre-check)
  2. Initialize nextLink   /me/chats/{chatId}/messages?$top=50
  3. Initialize messageIds []

  4. Collect_All_Message_Ids  (Until nextLink is empty)   ← page through ALL messages
       a. Get_Messages_Page        GET  {nextLink}
       b. Keep_Deletable_Messages  Filter: messageType == 'message' AND deletedDateTime is null
       c. Collect_Page_Ids         For each kept message → Append its id to messageIds
       d. Set_Next_Link            nextLink = @odata.nextLink (or '' to stop)

  5. Delete_Each_Message  (For each id, sequential)
       • Soft_Delete_Message       POST /me/chats/{chatId}/messages/{id}/softDelete
```

### Design decisions (and why)

- **Soft-delete, not delete.** Microsoft Graph has **no `DELETE` for a chat message**;
  the only way to remove one is `POST …/messages/{id}/softDelete`
  ([docs](https://learn.microsoft.com/graph/api/chatmessage-softdelete?view=graph-rest-1.0)).
  Removed messages are recoverable for a while via
  [`undoSoftDelete`](https://learn.microsoft.com/graph/api/chatmessage-undosoftdelete?view=graph-rest-1.0).
- **Collect first, then delete.** Deleting while you page can skip messages, re-loop, or
  invalidate the paging cursor. Snapshotting all ids first (paging via `@odata.nextLink`)
  is order-independent and always terminates.
- **Grow the id list with "Append to array variable", not "Set variable".** Power
  Automate rejects a `Set variable` whose new value references the same variable
  (`Self reference is not supported`), so ids are appended one at a time in a sequential
  inner `For each`.
- **Filter in the flow, not the URL.** `$filter=deletedDateTime eq null` is **rejected**
  by Graph (only `lastModifiedDateTime`/`createdDateTime` are filterable). The
  `Keep_Deletable_Messages` step filters client-side and also drops `systemEventMessage`
  items you can't delete.
- **`$top=50`** is the API maximum; **sequential deletes** (`concurrency = 1`) stay under
  Graph's chat-write throttling, and the platform's default retry handles the rare `429`.
- **Target the self-chat by its `48:notes` alias.** The Teams connector's HTTP action
  only allows Graph paths under `me|users|teams` + `chats|messages|…`, so a bare
  `GET /me` (to look up your id) is **rejected**. `48:notes` is the Teams alias for the
  self-chat; if your tenant needs the full `19:…@unq.gbl.spaces` id instead, swap it into
  `Initialize chatId` (see [Confirm your self-chat ID](#confirm-your-self-chat-id)).

### Permissions
The Teams connector calls Graph with **delegated** permission; soft-delete needs
**`Chat.ReadWrite`** (not supported for personal Microsoft accounts). The connector
usually already carries this — if a delete returns `403`, see Troubleshooting.

---

## Confirm your self-chat ID

The flow targets **`48:notes`** (the Teams alias for your self-chat) by default. If a run
fails at `Get_Messages_Page` with a **404**, your tenant needs the full Graph id instead —
get it in 20 seconds:

1. Open [Graph Explorer](https://developer.microsoft.com/graph/graph-explorer), sign in.
2. Run `GET https://graph.microsoft.com/v1.0/me/chats?$expand=members` and find the chat
   whose **only member is you** — that's the self-chat. Copy its `id` (usually
   `19:…_…@unq.gbl.spaces`).
3. In the flow, open **`Initialize chatId`** and set its value to that literal id.

---

## Troubleshooting

| Symptom | Cause & fix |
|---|---|
| `Get_Messages_Page` 401/403 | Teams connection not authorized — recreate it under **Data → Connections** and re-point the action. |
| `Get_Messages_Page` 404 / "invalid chat id" | `48:notes` isn't accepted as a Graph chat id for your tenant — set the real id in `Initialize chatId` (see [Confirm your self-chat ID](#confirm-your-self-chat-id)). |
| `Get_Messages_Page` "resource/object is not supported" | The connector only allows `me\|users\|teams` + `chats\|messages\|…` paths. The flow stays within those; if you edited a URI, keep it under `/me/chats/…`. |
| `Soft_Delete_Message` 403 | Connector lacks **`Chat.ReadWrite`** consent — test `POST /me/chats/{id}/messages/{id}/softDelete` in Graph Explorer (it'll prompt for the scope), or ask an admin. |
| Some deletes 429 | Throttling on large chats; platform retries. Just run again — already-deleted messages are skipped by the filter. |
| Only *some* messages gone | `softDelete` only removes your own, non-system messages. In a self-chat that's everything except system notices (which can't be removed). |

---

## Appendix A: why not a typed command?

The original goal was to type `/clear` in the self-chat and have it wipe itself. We
built that on the Teams **"When keywords are mentioned"** trigger and fixed a chain of
real issues — but it ultimately can't work for the self-chat. The trail:

1. **`Self reference is not supported`** on save — the id accumulator used a
   self-referencing `Set variable`. Fixed with `Append to array variable`.
2. **`An identifier was expected at position 0`** — the keyword search is parsed as an
   OData/KQL query, which rejects a leading `/`. Switched the keyword to `clearchat`.
3. **`'RequestBody/chats' is no longer present in the operation schema`** — the
   *designer's* static schema check flags this param… but the **runtime requires it**:
   without it the subscription resource becomes `chats//messages` (empty chat id) and
   fails with *"Subscription is not supported."* So the param must stay.
4. **With the param, the subscription is created (HTTP 200 / inner 204) — but the flow
   never fires** when you type the keyword in the self-chat.

Step 4 is the dealbreaker: Teams will happily *subscribe* to `48:notes`, but it doesn't
*deliver* keyword/change notifications for the chat-with-yourself (consistent with the
documented limits on triggering flows from the self-chat). A button (or a scheduled poll
that reads the chat directly) is the only reliable way. We chose the **button**.

## Appendix B: the original `v6` bugs

The first attempt (`ClearMessageHistory_v6`, in `original/`) failed its tests for two
independent reasons, both fixed in this flow:

- `GET …/messages?$filter=deletedDateTime eq null` → **HTTP 400** (`deletedDateTime`
  isn't filterable).
- `DELETE …/messages/{id}` → **HTTP 405/404** (no `DELETE` for chat messages; use
  `POST …/softDelete`).

---

## References
- [chatMessage: softDelete — `POST …/softDelete`, `Chat.ReadWrite`](https://learn.microsoft.com/graph/api/chatmessage-softdelete?view=graph-rest-1.0)
- [chatMessage: undoSoftDelete (recover within retention)](https://learn.microsoft.com/graph/api/chatmessage-undosoftdelete?view=graph-rest-1.0)
- [List messages in a chat — supported `$filter`/`$orderby`/`$top`](https://learn.microsoft.com/graph/api/chat-list-messages?view=graph-rest-1.0#optional-query-parameters)
- [chat resource — one-on-one chat id format](https://learn.microsoft.com/graph/api/chat-get?view=graph-rest-1.0#examples)
