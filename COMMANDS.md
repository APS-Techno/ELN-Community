# Conversation shorthand

These commands describe user intent, not installed shell commands or extra permissions. Root and scoped AGENTS rules still apply. Resolve all files in the current Community checkout; do not use a legacy task list or sibling host.

| Request | Action |
| --- | --- |
| `todo: <description>` | Record a task in the current task list when the user requests task tracking. |
| `wip: <description>` | Record work in progress in that same list. |
| `done: <task>` | Record completion only when the required evidence and user acceptance exist. Do not claim an untested change works. |
| `refactor: <file>` | Refactor the named area without adding unrelated behavior. |
| `fix: <file:line or bug>` | Diagnose and fix the named problem. |
| `implement: <method or task>` | Implement the stated behavior and its acceptance criteria. |
| `document: <file>` | Add or update documentation for the named area. |
| `analyze: <area>` | Analyze the named code or directory; report evidence and uncertainty. |
| `review: <file>` | Review the named code and report findings; do not edit unless asked. |
| `find: <pattern>` | Search bounded current source scopes. |
| `build` | Use the Community helper with Win32 Debug and the relevant target. If no target is stated, its default is StorageTests; report which target was used. No host launch, install, or deployment. |
| `test: <feature>` | Build and run the relevant synthetic local suite with the helper. Do not test against user notebooks or Commercial live services. |
| `commit: <message>` | Commit only the explicitly authorized task changes in the owning repository. Do not push or tag. |
| `status` | Display the existing task summary and observed progress. Do not implement. |
| `next` or `next:` | Read and display the full current task list, then suggest the next open task. Do not implement it. |
| `help:` | Display this reference. |

If no current task list exists, say so. A display request does not authorize creating one. Separate code completion, exercised verification, and running-application acceptance in status reports.

When a commit is explicitly authorized, historical message prefixes remain available: `+` for additions, `*` for fixes or changes, and `~` for internal work. The migration itself authorizes no commit, release, version bump, or publication.
