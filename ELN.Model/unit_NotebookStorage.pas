unit unit_NotebookStorage;

interface

uses
  System.SysUtils;

type
  // Backend-neutral attachment relocation. No database, UI or network units.
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

  // Optional inspection used by attachment repair without loading file bytes.
  // StatusCode preserves provider diagnostics; 404 means confirmed absence.
  INotebookStorageInspection = interface
    ['{26F112DE-3D37-4F8B-835E-72D784D409A1}']
    function TryGetFileInfo(const RelativePath: string;
      out StatusCode: Integer; out ContentLength: Int64): Boolean;
    function ListCollection(const RelativePath: string;
      out Names: TArray<string>): Boolean;
  end;

implementation

end.
