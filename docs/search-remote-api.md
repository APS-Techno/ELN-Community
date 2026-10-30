# Remote semantic search: HTTP contract

This document gives the HTTP contract between `TRemoteSemanticSearch` (unit `ELN.Search/unit_RemoteSemanticSearch.pas`) and a search server. The client implements `ISemanticSearch` (`IsRemote = True`). The Desktop search dialog and the MCP tool `search_semantic` use it in the same way as the local search.

The JSON names are the names of the MCP tool `search_semantic` (`ELN.MCPServer/unit_ToolsNavigation.pas`). A server must write a response with the same names as the tool output.

## Client configuration

The host gives three values. The client has no credential logic.

| Value | Meaning |
| --- | --- |
| `BaseUrl` | The server address, for example `https://search.lab.local:8443/eln`. It must start with `http://` or `https://`. The client removes a `/` at the end. |
| `GetToken` | A function that returns the bearer token. The client calls it once for each request. After a 401 response, it calls it one more time (see "Errors"). It runs on the thread of the search or on the status thread of the client, thus it must be thread-safe. |
| `TimeoutMs` | The time limit of one search or one status request, in milliseconds. It includes the retry after a 401 response. |

## Requests

All requests send these headers:

- `Authorization: Bearer <token>`
- `Accept: application/json`
- `Content-Type: application/json; charset=utf-8` (POST only)

The client does not follow redirects. A redirect is an error (it could send the token to a different host).

### `POST {base}/search/semantic`

Request body:

```json
{
  "query": "reflectivity of Ni/C multilayers",
  "top_k": 10,
  "project_ids": [3, 5],
  "filters": {
    "folder_id": 12,
    "item_types": ["Measurement", "Testing"],
    "levels": ["Proc"],
    "action_type_id": 4,
    "date_field": "modified",
    "date_from": "2026-01-31",
    "date_to": "2026-02-28",
    "values": [
      {"value_type": "Period", "min": 2, "max": 3.5, "unit": "nm", "rec_type": "TEST_RESULT"},
      {"value_type": "Density"}
    ]
  },
  "rerank": true
}
```

| Field | Required | Type | Default | Meaning |
| --- | --- | --- | --- | --- |
| `query` | yes | string | - | The search text. |
| `top_k` | no | integer, 1 to 50 | 10 | The maximum number of item groups. |
| `project_ids` | yes | integer array, can be empty | - | The projects that the caller can see. The client always sends it. The server intersects it with the projects that the token user can read. It never adds a project. |
| `filters` | no | object | `{}` | The filter. The client always sends it. `{}` means no filter. The server resolves the filter. |
| `rerank` | no | boolean | `true` | `true`: the server can rerank with the cross-encoder. `false`: no rerank. |

### Validation

The rules in this section are the rules of the MCP tool `search_semantic` (`ELN.MCPServer/unit_ToolsNavigation.pas`, functions `ReadSemanticFilter` and `HandleSearchSemantic`) and of the filter resolver (`ELN.Model/unit_SemanticSearchFilter.pas`, `ResolveSemanticFilter`). These functions are private to the Community hosts, thus a server must implement the same rules. Then the MCP tool gives the same result and the same message for a local search and for a remote search.

The server does the steps in this order. It stops at the first error.

1. The body must be a JSON object. Else: 400 `invalid_request`, `The request body must be a JSON object.`
2. `query` must be present. Else: 400 `invalid_request`, `Missing required parameter: query`.
3. `top_k`: absent gives 10. A value below 1 or above 50: 400 `invalid_request`, `top_k must be an integer from 1 to 50.`
4. `project_ids` must be present: else 400 `invalid_request`, `Missing required parameter: project_ids`. It must be an array: else `project_ids must be an array.` Each element must be an integer: else `project_ids must contain only integers.`
5. `rerank`: absent gives `true`. A value that is not `true` or `false`: 400 `invalid_request`, `rerank must be true or false.`
6. `filters`: absent or `null` gives `{}`. A value that is not an object: 400 `invalid_request`, `filters must be an object.` Then the filter fields, in the order of the table "Filter fields" below.
7. Short query: when the length of `query` after trimming is less than 2 characters, the answer is 200 with `{"groups": [], "reranked": false, "index": {...}}` and no `filters_applied`. Trimming removes characters with a code of U+0020 or less at the two ends. The length counts UTF-16 code units. Step 7 comes after the shape checks of step 6 and before the filter resolution, so a short query with an unknown unit gives 200.
8. Scope: the scope is `project_ids` intersected with the projects that the token user can read. When the scope is empty, the answer is the same as in step 7.
9. Filter resolution (only for a filter that is not empty): see "Filter resolution". Errors: 400 `invalid_filter`.
10. The search: 200 (see "Response 200").

Steps 3 to 6 give the messages above also for a value of the wrong JSON type (for example `null` or `2.5` for `top_k`, or an array for `query`: `query must be a string.`). The MCP tool gives an RTL conversion message in these cases ("... is not a valid Integer value or conversion is not supported"), so that text is not part of the contract. The MCP tool also accepts a numeric string (`"5"`) or `true` (as 1) for an integer field, and the JSON text of a number or of `true`/`false` for a string field. `null` for `query` is an empty text (a short query). A server can accept these forms. The client never sends them.

#### Filter fields

The client sends a field only when the filter uses it. `null` has the same meaning as an absent field, except for `folder_id` and `action_type_id` (see the note above about the wrong JSON type).

| Field | Type | Absent | Rule. Error message (400 `invalid_request`) |
| --- | --- | --- | --- |
| `folder_id` | integer | No folder filter. | 1 or more. `folder_id must be a positive integer.` |
| `item_types` | string array | No type filter. `[]` is the same. | An array: `item_types must be an array.` Only strings: `item_types must contain only strings.` |
| `levels` | string array | No level filter. `[]` is the same. | An array: `levels must be an array.` Only strings: `levels must contain only strings.` |
| `action_type_id` | integer | No action type filter. | 1 or more. `action_type_id must be a positive integer.` |
| `date_from` | string | No lower date limit. | A date without a time part. The text must not contain `T`, `:` or a space, and it must be a valid ISO 8601 date: `date_from must be an ISO 8601 date, for example 2026-01-31.` |
| `date_to` | string | No upper date limit. | The same rule: `date_to must be an ISO 8601 date, for example 2026-01-31.` |
| `date_field` | string | `created` when `date_from` or `date_to` is present, else no date filter. | `created` or `modified`, case-insensitive, spaces at the ends ignored: `date_field must be "created" or "modified".` |
| `values` | array of objects | No value filter. | An array: `values must be an array.` Each entry an object: `values[<i>] must be an object.` (`<i>` counts from 0.) |
| `values[i].value_type` | string | Error. | Not empty and not only spaces: `values[<i>].value_type is required.` |
| `values[i].min`, `max` | number | No limit on that side. | A JSON number: `values[<i>].min must be a number.` (or `.max`). |
| `values[i].unit` | string | The unit of the value type. `""` is the same. | See "Filter resolution". |
| `values[i].rec_type` | string | Both record types. `""` is the same. | See "Filter resolution". |

The client sends dates as `yyyy-mm-dd`. The tool parser (`ISO8601ToDate`) also accepts the other ISO 8601 date forms, for example `20260131`, `2026-1-31`, `2026-031` (ordinal) and `2026-W05-1` (week). It refuses a date that does not exist (`2026-02-30`).

#### Filter resolution

The server resolves a filter that is not empty in this order (400 `invalid_filter` for each error):

1. `item_types`: each name, with spaces at the ends removed and case-insensitive, must be one of `Synthesis`, `Treatment`, `Measurement`, `Testing`, `Characterization`, `Computing`, `Specimen`, `Model`, `Other`, `Wiki`. Else: `Unknown item type "<name as sent>".`
2. `levels`: each name must be one of `Proc`, `Item`, `Action`, `Folder` (same comparison). Else: `Unknown item level "<name as sent>".`
3. Dates: when `date_field` is set and both dates are present, the day of `date_from` must not be after the day of `date_to`. Else: `The start date is after the end date.`
4. `values`, each entry in order:
   1. `rec_type`, with spaces at the ends removed and case-insensitive, must be `EXP_CONDITION` or `TEST_RESULT`. Else: `Unknown record type "<rec_type as sent>" (use EXP_CONDITION or TEST_RESULT).`
   2. `min` and `max` must be finite. Else: `A limit for value type "<value_type>" is not a finite number.` (JSON cannot give a value that is not finite.)
   3. `value_type` is compared with the title and with the symbol of each value type, case-insensitive, without trimming. It can match more than one value type; then an item matches when it agrees with one of them. For each match, the limits change to the unit of that value type: an empty `unit` or the same unit gives no change. An unknown unit: `Unit "<unit>" is not known.` A unit of a different dimension: `Unit "<unit>" cannot be converted to "<units of the value type>", the unit of value type "<title>".` After the conversion, `min` above `max`: `The minimum is greater than the maximum for value type "<title>".`
   4. No value type matches: `Value type "<value_type>" does not exist.`
5. `folder_id` must be a folder of a project in the scope (step 8). Else: `The folder does not exist or is not available.` The filter then includes the subfolders in the same project, and the search uses only the project of the folder.

`action_type_id` has no check. An unknown id gives no items.

Meaning of a resolved filter:

- All filter fields must agree (AND). All `values` entries must agree (AND).
- `min` and `max` are inclusive, in the unit of the value type.
- `date_from` includes its full day (from 00:00). `date_to` includes its full day (before 00:00 of the next day). The server compares the day with the stored date of the item, with no time zone conversion.
- `date_field` = `modified`: an item without a modified date never agrees, also when no date is given.
- Deleted items never agree.

`filters_applied` has the format of the local implementation (`TLocalSemanticSearch`): `folder_id`, `item_types` and `levels` (names trimmed), `action_type_id`, `date_field` with `date_from` and `date_to` as `yyyy-mm-dd`, and `values` with one entry for each matched value type: `value_type` (the title), `value_type_id`, `unit` (the unit of the value type), `min` and `max` (converted), `rec_type` (the canonical name), `requested_unit` (the `unit` that was sent, trimmed, when not empty).

### Response 200

```json
{
  "groups": [
    {
      "item_id": 101,
      "project_id": 3,
      "score": 0.0325,
      "sources": ["vector", "trigram"],
      "passages": [
        {"field": "file_text", "file_id": 5000000001, "snippet": "Ni/C period 2.5 nm", "score": 0.0325}
      ]
    }
  ],
  "reranked": true,
  "index": {"complete": false, "indexed_passages": 481, "pending_passages": 7, "files_pending": 2},
  "filters_applied": {"folder_id": 12, "values": [{"value_type": "Period", "value_type_id": 4, "unit": "nm", "min": 2}]}
}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `groups` | array | The item groups in rank order. |
| `groups[].item_id`, `project_id` | integer | The item and its project. |
| `groups[].score` | number | The rank score. It is not a probability. |
| `groups[].sources` | string array | `vector`, `words`, `trigram`. |
| `groups[].passages` | array | At least one passage. The first passage is the best match. |
| `passages[].field` | string | `title`, `description`, `properties`, `tags`, `entry_title`, `protocol_form`, `value_description`, `file_name`, `file_text`. |
| `passages[].file_id` | integer | The attachment id, 0 for a passage that is not from a file. |
| `passages[].snippet` | string | The passage text, at most 200 characters. |
| `passages[].score` | number | The passage score. |
| `reranked` | boolean | `true` when the cross-encoder ordered the groups. |
| `index` | object | The index state of the server, with the names of the MCP tool output. |
| `filters_applied` | object | Optional. The resolved filter, in the format of the MCP tool output. The client gives it to the caller without change. Absent or `null` means no filter. |

The server can send more fields (for example `item_title`, `project_path`). The client ignores them. The names in `field` and `sources` are the constants `PassageFieldNames` and `HitSourceNames` in `unit_SemanticSearchApi`. The MCP tool uses the same constants.

The client maps `index` to `TSemanticSearchStatus`: `State = ssIdle`, `LastSyncComplete = complete`, `IndexedPassages`, `PendingPassages`, `FilesTotal = files_pending`, `FilesDone = 0`. Thus `IsComplete` and the MCP `index` output are the same as the server values.

### `GET {base}/search/status`

Response 200:

```json
{
  "index": {"complete": true, "indexed_passages": 481, "pending_passages": 0, "files_pending": 0},
  "reranker_available": true
}
```

## Errors

An error response has the body `{"code": "<word>", "message": "<text for the user>"}`.

| HTTP | Suggested `code` | Client result |
| --- | --- | --- |
| 400 | `invalid_request` (shape), `invalid_filter` (resolution) | `ESemanticFilterError` with `message` unchanged. The messages are in "Validation". |
| 401 | `unauthorized` | The client calls `GetToken` one more time and sends the request again, one time. A second 401 gives `ESemanticSearchAccessDenied`. |
| 403 | `forbidden` | `ESemanticSearchAccessDenied` ("The search server refused access: ..."). |
| 503 | `unavailable` | `ESemanticSearchUnavailable` ("The search server is not available: ..."). |
| other | - | `ESemanticSearchUnavailable` with the HTTP status. |

These conditions also give `ESemanticSearchUnavailable`:

- No answer within `TimeoutMs`. The client raises the error not later than `TimeoutMs` plus 1 s. On Windows, the client cancels the request at the time limit, because WinHTTP rounds its own time limits up to steps of approximately 4 s.
- No connection.
- A server certificate that the operating system does not trust (see "Server certificate").
- A response that is not valid for this contract (not JSON, a missing field, an unknown `field` or `sources` name, a group without passages).

`ESemanticSearchUnavailable` also sets the cached status to `ssFailed` with the message in `LastError`. 400, 401 and 403 do not change the cached status.

## Access rules

1. The server finds the readable projects of the caller from the token. `project_ids` can only make this set smaller.
2. The visible set is always explicit. An empty `VisibleProjectIds` means no project, in the local search and in the remote client. The remote client then returns an empty result and sends no request. In all other cases it sends `project_ids`. The client removes every group whose `project_id` is not in `VisibleProjectIds`, and adds the number of removed groups to `TSemanticSearchStatus.DroppedGroups` (a total for the life of the client). A value above 0 shows a server fault.
3. The MCP tool and the Desktop dialog also apply their own access checks to each item. The remote client does not replace them.

## Status and reranker

`Status` and `RerankerAvailable` run on the UI thread. They never wait for the network:

- They return the cached state.
- A search response updates the cached index state.
- When the cache is older than 10 s, a call to `Status` or `RerankerAvailable` wakes a background thread. This thread sends `GET /search/status` and updates the cache. Not more than one status request is open at a time, and not more than one starts in each 10 s.
- `RerankerAvailable` is `false` until the first status response.

## Server certificate

The client validates the server certificate against the trust store of the operating system (Windows: the certificate store; Linux: the CA bundle that curl uses). There is no pin and no mode that accepts all certificates.

A server with a self-signed certificate is possible only when its certificate, or the certificate of the lab CA that signed it, is trusted on each client computer. The name in the certificate must agree with the host name in `BaseUrl`.

When the validation fails, `System.Net.HttpClient` raises `ENetHTTPCertificateException` (unit `System.Net.HttpClient`, text "Server Certificate Invalid or not present"). The client changes it to `ESemanticSearchUnavailable`: "The certificate of the search server `<BaseUrl>` is not trusted by this computer (...). Install the server certificate or its authority in the trust store of the operating system." The TLS handshake stops before the request is sent.

## Tests

`ELN.Community.Tests/test_RemoteSemanticSearch.pas` (in `SearchIndexTests`, Win64 and Linux64). The HTTP tests use a fake transport (`IRemoteSearchTransport`). One of them gives the certificate failure of the transport (`ENetHTTPCertificateException`) and checks the message. One test uses the real transport against a TCP socket on 127.0.0.1 that does not answer, for the time limit.
