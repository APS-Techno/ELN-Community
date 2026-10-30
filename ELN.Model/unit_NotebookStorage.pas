unit unit_NotebookStorage;

interface

uses
  System.SysUtils,
  System.Classes;

type
  IFileRelocator = interface
    ['{C7C6C0F0-1A2B-4F2E-9F6E-2B7D5E3A4C10}']
    procedure MoveFile(const OldPath, NewPath: string);
  end;

  // Paths are relative to the backend root. Byte operations preserve binary
  // attachments; protocol-specific prefixes belong in host adapters.
  INotebookStorage = interface(IFileRelocator)
    ['{31881559-4748-4078-B150-39520B69D97C}']
    function ReadBytes(const RelativePath: string): TBytes;
    procedure WriteBytes(const RelativePath: string; const Data: TBytes);
    procedure CopyIn(const SourcePath, RelativePath: string);
    procedure CopyOut(const RelativePath, TargetPath: string);
    function Exists(const RelativePath: string): Boolean;
    // Missing files are already deleted; other failures must raise.
    procedure DeleteFile(const RelativePath: string);
  end;

  // Optional local save transaction. Hold this reference until metadata commit
  // or rollback finishes. It owns the original and installed file identities;
  // concurrent writers/deleters are denied, and namespace collisions never
  // overwrite another file. Failed compensation retains recovery bytes.
  // Successful Commit/Rollback releases OS handles explicitly, independently
  // of compiler-managed interface temporaries. A completed update is not reused.
  INotebookFileUpdate = interface
    ['{2DDE16FC-3899-4B5C-A2E3-BE7021E0EC2D}']
    function Exists: Boolean;
    // Caller frees the stream before Commit/Rollback/release. It must not write.
    function OpenRead: TStream;
    procedure CopyOut(const TargetPath: string);
    procedure InstallFrom(const SourcePath: string);
    procedure Rollback;
    // Call only after database commit. Nonthrowing handle release and
    // retired-file cleanup; failed cleanup retains recovery bytes.
    procedure Commit;
  end;

  INotebookStorageUpdates = interface
    ['{9A36C479-2970-451A-9560-4D8097BA4C89}']
    function BeginFileUpdate(const RelativePath: string): INotebookFileUpdate;
  end;

  // Optional inspection used by attachment repair without loading file bytes.
  // StatusCode preserves provider diagnostics; 404 means confirmed absence.
  INotebookStorageInspection = interface
    ['{26F112DE-3D37-4F8B-835E-72D784D409A1}']
    function TryGetFileInfo(const RelativePath: string;
      out StatusCode: Integer; out ContentLength: Int64): Boolean;
    function ListCollection(const RelativePath: string;
      out Names: TArray<string>): Boolean;
  end;

  INotebookStorageStamp = interface
    ['{4E8B2F61-7C35-4D9A-A1B0-6F3D52C9E847}']
    function TryGetFileStamp(const RelativePath: string;
      out Size, LastWrite: Int64): Boolean;
  end;

implementation

end.
