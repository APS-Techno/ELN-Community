unit unit_FileTypeLink;

interface

uses
  SysUtils,
  Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.DynamicProperties,
  Aurelius.Types.Nullable,
  Aurelius.Types.Blob,
  Aurelius.Types.Proxy,
  unit_ActionType,
  unit_FileType;

type
  TFileTypeLink = class;

  TFileTypeLinks = TList<TFileTypeLink>;

  [Entity]
  [Table('FileTypeLinks')]
  [Description('')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TFileTypeLink = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('')]
    FId: Integer;

    // This reference is not owned here. Cascading Evict would leave a stale
    // shared instance and cause EObjectAlreadyPersistent on a later save.
    [Association([TAssociationProp.Lazy], [])]
    [JoinColumn('ActionTypeID', [], 'Id')]
    [Description('')]
    FActionType: Proxy<TActionType>;

    [Association([TAssociationProp.Lazy], [])]
    [JoinColumn('TypeID', [], 'Id')]
    [Description('')]
    FFileType: Proxy<TFileType>;

    [Column('CreatedDate', [TColumnProp.Required])]
    [Description('')]
    FCreatedDate: TDateTime;

    [Column('ModifiedDate', [])]
    [Description('')]
    FModifiedDate: Nullable<TDateTime>;

    [Column('CreatedBy', [])]
    [Description('')]
    FCreatedBy: Nullable<Integer>;

    [Column('ModifiedBy', [])]
    [Description('')]
    FModifiedBy: Nullable<Integer>;

    function GetActionType: TActionType;
    procedure SetActionType(const Value: TActionType);
    function GetFileType: TFileType;
    procedure SetFileType(const Value: TFileType);
  public
    property Id: Integer read FId write FId;
    property ActionType: TActionType read GetActionType write SetActionType;
    property FileType: TFileType read GetFileType write SetFileType;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property CreatedBy: Nullable<Integer> read FCreatedBy write FCreatedBy;
    property ModifiedBy: Nullable<Integer> read FModifiedBy write FModifiedBy;
  end;

implementation


function TFileTypeLink.GetActionType: TActionType;
begin
  Result := FActionType.Value;
end;

procedure TFileTypeLink.SetActionType(const Value: TActionType);
begin
  FActionType.Value := Value;
end;

function TFileTypeLink.GetFileType: TFileType;
begin
  Result := FFileType.Value;
end;

procedure TFileTypeLink.SetFileType(const Value: TFileType);
begin
  FFileType.Value := Value;
end;

initialization
  RegisterEntity(TFileTypeLink);

end.
