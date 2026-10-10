unit unit_Hypothesis;

{
  Every enum here is stored as an integer ordinal. APPEND ONLY: reordering or
  inserting a member silently changes the meaning of every stored row.

  Column 'ChangeText', not 'Change': CHANGE is a reserved word in MySQL.
}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable;

type
  [Enumeration(TEnumMappingType.emInteger)]
  THypothesisStatus = (hsProposed, hsApproved, hsRejected, hsInReview,
    hsAccepted, hsAbandoned);

  [Enumeration(TEnumMappingType.emInteger)]
  THypothesisOutcome = (hoSupported, hoRefuted, hoInconclusive);

  [Enumeration(TEnumMappingType.emInteger)]
  THypothesisRunRole = (hrrRun, hrrReference);

  THypothesisGate = (hgApproveProposals, hgAcceptConclusions);

const
  HypothesisStatusNames: array[THypothesisStatus] of string =
    ('Proposed', 'Approved', 'Rejected', 'InReview', 'Accepted', 'Abandoned');
  HypothesisOutcomeNames: array[THypothesisOutcome] of string =
    ('Supported', 'Refuted', 'Inconclusive');
  HypothesisRunRoleNames: array[THypothesisRunRole] of string =
    ('Run', 'Reference');
  /// <summary>Also the JSON keys of the approval policy.</summary>
  HypothesisGateNames: array[THypothesisGate] of string =
    ('approveProposals', 'acceptConclusions');

type
  THypothesis = class;
  THypotheses = TList<THypothesis>;

  [Entity]
  [Table('Hypotheses')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  [DBIndex('IX_Hypotheses_ProjectId', 'ProjectId')]
  THypothesis = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('ProjectId', [TColumnProp.Required])]
    FProjectId: Integer;

    [Column('ParentId', [])]
    FParentId: Nullable<Integer>;

    [Column('Title', [TColumnProp.Required], 255)]
    FTitle: string;

    [Column('Statement', [TColumnProp.Lazy], 65536)]
    FStatement: string;

    [Column('ChangeText', [TColumnProp.Lazy], 65536)]
    FChange: string;

    [Column('Status', [TColumnProp.Required])]
    FStatus: THypothesisStatus;

    [Column('Outcome', [])]
    FOutcome: Nullable<THypothesisOutcome>;

    [Column('Conclusion', [TColumnProp.Lazy], 65536)]
    FConclusion: string;

    [Column('KeyValueTypeId', [])]
    FKeyValueTypeId: Nullable<Integer>;

    [Column('CreatedBy', [TColumnProp.Required])]
    FCreatedBy: Integer;

    [Column('CreatedDeviceId', [])]
    FCreatedDeviceId: Nullable<Integer>;

    [Column('CreatedDate', [TColumnProp.Required])]
    FCreatedDate: TDateTime;

    [Column('ContentHash', [], 64)]
    FContentHash: string;

    // Touched by every write that changes the hypothesis OR its run/evidence
    // rows, so that write also bumps [Version]: a second client that loaded
    // the node earlier then fails the optimistic lock instead of attaching
    // to a node that has meanwhile been sealed.
    [Column('ModifiedDate', [])]
    FModifiedDate: Nullable<TDateTime>;

    [Column('Version', [TColumnProp.Required])]
    [Version]
    FVersion: Integer;
  public
    // Aurelius only maintains [Version] on Update/Delete (optimistic-lock
    // check + increment); on Insert it writes whatever the field already
    // holds. Start new hypotheses at version 1 so the very first row is
    // never indistinguishable from an entity Aurelius has not versioned yet.
    constructor Create;
    property Id: Integer read FId write FId;
    property ProjectId: Integer read FProjectId write FProjectId;
    property ParentId: Nullable<Integer> read FParentId write FParentId;
    property Title: string read FTitle write FTitle;
    property Statement: string read FStatement write FStatement;
    property Change: string read FChange write FChange;
    property Status: THypothesisStatus read FStatus write FStatus;
    property Outcome: Nullable<THypothesisOutcome> read FOutcome write FOutcome;
    property Conclusion: string read FConclusion write FConclusion;
    property KeyValueTypeId: Nullable<Integer> read FKeyValueTypeId write FKeyValueTypeId;
    property CreatedBy: Integer read FCreatedBy write FCreatedBy;
    property CreatedDeviceId: Nullable<Integer> read FCreatedDeviceId write FCreatedDeviceId;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ContentHash: string read FContentHash write FContentHash;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    /// <summary>Sets ModifiedDate to AUtcNow, or 1 ms past the stored value
    /// when the clock has not moved on, so the row is always dirty and the
    /// next Flush always bumps [Version].</summary>
    procedure MarkModified(const AUtcNow: TDateTime);
    property Version: Integer read FVersion write FVersion;
  end;

implementation

uses
  System.DateUtils;

constructor THypothesis.Create;
begin
  inherited Create;
  FVersion := 1;
end;

procedure THypothesis.MarkModified(const AUtcNow: TDateTime);
begin
  if FModifiedDate.HasValue and (AUtcNow <= FModifiedDate.Value) then
    FModifiedDate := IncMilliSecond(FModifiedDate.Value)
  else
    FModifiedDate := AUtcNow;
end;

initialization
  RegisterEntity(THypothesis);

end.
