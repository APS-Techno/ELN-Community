# Lazy collections of TItem and TProject

From version 2.3.1.66, these collections load lazily (`TAssociationProp.Lazy`):

- `TItem.Entries`;
- `TItem.Files`;
- `TItem.Values`;
- `TProject.Folders`.

A load of a `TItem` or a `TProject` runs no query for them. The first read of a list runs one query through the manager that loaded the object.

## Rules

1. Read a list only on an object that its manager still holds. On an evicted object with an unloaded list, a read raises `EObjectManagerNotSet`; it does not load. Find the object again by id (`Find<TItem>(Id)`) before the read.
2. To know whether a list is loaded without loading it, use `TItem.EntriesLoaded`, `TItem.FilesLoaded`, `TItem.ValuesLoaded` or `TProject.FoldersLoaded`.
3. `Evict` cascades only into loaded lists. An evict helper that must also remove children of an unloaded list must find them with a query and evict them itself. An example is `TRecycleBinModel.PurgeItems`.
4. Do not load a list only to evict it. `TItemModel.EvictCache` evicts only the children of loaded lists.
5. A new object (`TItem.Create`, `TProject.Create`) has empty lists that work without a manager. `AddItem` returns an evicted item; `AddValue`, `AddFile` and `AddNote` attach it again with `Update`.
6. A loop over the lists of many objects runs one query for each object. On a hot path, read the children of all objects with a batched query, and use the object's own list when it is loaded. `TItemTreeVM` (`EntriesOf`, `FilesOf`, `ValuesOf`) and `TProjectTreeVM` (`FoldersOf`) show the pattern, including the eviction of the children that the batch read.

## Tests

- `ELN.Community.Tests/test_LazyCollections.pas` pins the Aurelius behaviour that these rules depend on.
- `ELN.Community.Tests/test_DesktopLoadStatements.pas` counts the statements of the Desktop load paths.

The DUnitX leak monitor of the test runners is not active. Leak tests use `GetMemoryManagerState` deltas.
