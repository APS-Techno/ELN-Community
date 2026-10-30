# Note to coding agent: add a `download_file` tool to the ELN MCP server

Status: `download_file` is implemented in `ELN.MCPServer/unit_ToolsFiles.pas` with tests in `ELN.Community.Tests/test_ValueSourceTools.pas`. The optional `stage_files` variant is not implemented.

## Problem

An agent cannot get the bytes of a file that is attached to an ELN item. A task that fits XRR curves from `.xrdml` files exposed this.

- `extract_file_data` returns only the parsed header fields for `.xrdml`. It returns no curve points.
- `list_file_columns` and `get_file_columns` refuse `.xrdml` ("File type not tabular").
- `upload_file` and `reattach_file` write to ELN. No tool reads the bytes out of ELN.
- An external analysis server (for example the xrc MCP server) reads only from its own inbox folder. For a file that exists only in ELN, the agent cannot give it to that server.

## Ownership

The tool goes into the shared tool library `ELN.MCPServer`. The Community host `ELN.Community.MCP/unit_CommunityMCPHost.pas` registers these tools.

## Existing code to reuse

| Need | Existing code |
| --- | --- |
| Read access to the file's project | `RequireFileRead` (`ELN.MCPServer/unit_ToolScope.pas`). Missing and out-of-scope files give the same `SOutOfScope` error, so a caller cannot probe other projects. |
| Deleted items | `check_storage` refuses a file of a deleted item (`AddRequestedFiles`, `unit_ToolsValueChecks.pas`). Do the same. |
| Storage path of the bytes | `AttachmentRelativePath(Project.FileFolder, Item.FolderName, F.FullName)` (`unit_FilePaths`). |
| Bytes out of storage | `INotebookStorage.CopyOut(RelativePath, LocalPath)`. `Storage.Exists` comes first. |
| MD5 | `THashMD5.GetHashStringFromFile`, compared with `Trim(F.Hash)` case-insensitively, as `CheckStoredFile` (`ELN.Model/unit_StorageCheck.pas`) does. |
| Storage status names | `TStorageCheckStatus` and `StorageCheckStatusCode`: `ok`, `missing`, `content_mismatch`, `no_hash`, `error`. |
| Local path confinement | `CheckUploadPathAllowed` (`unit_ToolsWrite.pas`). It resolves the full path, checks the root prefix, refuses `\\?\` and `\\.\` aliases, alternate data streams, path parts that end in a space or dot, and reparse points (junctions and symbolic links) on every part of the path. |
| Configured root | `TToolContext.UploadRoot`. The Community host sets it from `--upload-root`. When it is empty, the path tools are disabled. |
| Tool registration | `Registry.Register(..., tscProjectScoped)`. |

`check_storage` does not use the names `relocatable` and `lost`. These come from `repair_files`. Do not use them in `download_file`.

## Requested tool: `download_file`

Inputs:

- `file_id` (required).
- `dest_path` (required): absolute local path on the computer that runs the MCP server.
- `overwrite` (optional, default false).

Order of checks:

1. Confine `dest_path` with the same rules as `CheckUploadPathAllowed`, before any file system access. Extract the shared part of that procedure so that both directions use one guard; do not copy it. Use the error text "dest_path ..." for this tool, not "upload_file ...".
2. `RequireFileRead(Context, FileId)`. Refuse a file of a deleted item.
3. Refuse when `Context.Storage = nil` ("download_file needs notebook storage."), as `check_storage` does.
4. If `Storage.Exists` is false, return an error with status `missing`. Write no file.
5. `CopyOut` to a temporary file in the destination folder. Calculate the MD5 of the temporary file.
6. Move the temporary file to `dest_path`. When `overwrite` is false, the move must fail if `dest_path` exists (create-new semantics, no separate check before the move). When `overwrite` is true, replace the file. Delete the temporary file on every failure.

Destination folder:

- Create missing parent folders only under the allowed root. Apply the reparse-point check after the folders exist and before the move.

Result:

- `file_id`, `dest_path` (resolved full path), `size`, `md5`, `stored_hash`, and `storage_status` (`ok`, `content_mismatch` or `no_hash`).
- On `content_mismatch` and `no_hash`, write the file and report the status. The caller decides if the bytes are usable. A storage exception gives `error` and writes no file.

Read-only:

- Do not change ELN state. Do not write audit rows, values, or file records.

Allowed folders:

- First version: `dest_path` must be under `Context.UploadRoot`. The upload root is then both the import folder and the export folder. Record this in the tool description.
- If an export root separate from the upload root is necessary, add it to `TToolContext` and to both hosts (`--download-root`, registry `MCPDownloadRoot`). Empty means that the tool is disabled. Never use a broad default.

## Optional variant: stage into an analysis-server inbox

`stage_files`: inputs `file_ids[]` (maximum as in `check_storage`) and `subfolder`.

- `subfolder` is one path part. Refuse an empty value, `.`, `..`, path separators, `:` and the characters that `CheckFileTitleChars` refuses.
- The tool writes each file to `<root>\<subfolder>\<file name>` with the same steps as `download_file`. It is all-or-nothing: if one file fails, remove the files that this call wrote.
- `<root>` is a configured folder, not a constant in source code. A lab-specific inbox path must not be in Community source.
- Return `<subfolder>/<file name>` per file. ELN does not know the identifier format of the other server; the caller maps this value to that server's ID.

## Acceptance (Community tests, synthetic SQLite fixtures)

Add the tests next to the `check_storage` tests in `ELN.Community.Tests/test_ValueSourceTools.pas`.

1. A fixture file is downloaded under the upload root. `size` and `md5` match the source, and `storage_status` is `ok`.
2. A fixture file with changed bytes in storage gives `content_mismatch`, and the file is written.
3. A file with no bytes in storage gives an error with `missing`, and no file is at `dest_path`, also no temporary file.
4. A file in a project outside the session scope gives the same error as a file ID that does not exist.
5. `overwrite: false` refuses to replace an existing file and keeps its contents.
6. A `dest_path` outside the upload root, with `..`, or through a junction is refused before any write.
7. An empty upload root disables the tool.

## Not in scope

Do not change `delete_file`, `reattach_file`, `repair_files`, or the storage layout.
