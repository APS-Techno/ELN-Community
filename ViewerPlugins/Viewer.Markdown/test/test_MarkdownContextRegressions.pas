unit test_MarkdownContextRegressions;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMarkdownContextRegressions = class
  public
    [Test] procedure SavingPreviousFileDoesNotRenderInNewContext;
    [Test] procedure HiddenToolbarRemainsHiddenAfterDeferredParenting;
  end;

implementation

uses
  System.SysUtils, System.Classes, Vcl.Forms, RzButton, RzPanel,
  frame_MarkdownViewer, unit_ELNPluginCore;

type
  TCapturingLauncher = class(TInterfacedObject, IMarkdownEditorLauncher)
  public
    Saved: TProc<string>;
    procedure LaunchEditor(const LocalPath: string; ItemId: Integer; FileId: Int64;
      OnSaved: TProc<string>);
  end;

  TCountingEnumerator = class(TInterfacedObject, IElnFileEnumerator)
  public
    Requests: Integer;
    function GetItemFiles(ItemId: Integer): TArray<string>;
    function EnsureItemFilesInDir(ItemId: Integer; const TargetDir: string): TArray<string>;
  end;

procedure TCapturingLauncher.LaunchEditor(const LocalPath: string;
  ItemId: Integer; FileId: Int64; OnSaved: TProc<string>);
begin
  Saved := OnSaved;
end;

function TCountingEnumerator.GetItemFiles(ItemId: Integer): TArray<string>;
begin
  Inc(Requests);
  Result := nil;
end;

function TCountingEnumerator.EnsureItemFilesInDir(ItemId: Integer;
  const TargetDir: string): TArray<string>;
begin
  Inc(Requests);
  Result := nil;
end;

procedure TMarkdownContextRegressions.SavingPreviousFileDoesNotRenderInNewContext;
var
  PreviousLauncher: IMarkdownEditorLauncher;
  PreviousEnumerator: IElnFileEnumerator;
  Launcher: TCapturingLauncher;
  Enumerator: TCountingEnumerator;
  Frame: TframeMarkdownViewer;
  Host: TForm;
  I: Integer;
  Clicked: Boolean;
begin
  PreviousLauncher := MarkdownEditorLauncher;
  PreviousEnumerator := ElnFileEnumerator;
  Launcher := TCapturingLauncher.Create;
  Enumerator := TCountingEnumerator.Create;
  MarkdownEditorLauncher := Launcher;
  ElnFileEnumerator := Enumerator;
  Host := nil;
  try
    Host := TForm.CreateNew(nil);
    Host.HandleNeeded;
    Frame := TframeMarkdownViewer.Create(Host);
    Frame.Parent := Host;
    Frame.HandleNeeded;
    Frame.SetEditContext('C:\synthetic\A.md', 10, 100);
    Clicked := False;
    for I := 0 to Frame.ComponentCount - 1 do
      if Frame.Components[I] is TRzToolButton then
      begin
        TRzToolButton(Frame.Components[I]).OnClick(Frame.Components[I]);
        Clicked := True;
        Break;
      end;
    Assert.IsTrue(Clicked);
    Assert.IsTrue(Assigned(Launcher.Saved));
    Frame.SetEditContext('C:\synthetic\B.md', 20, 200);
    Launcher.Saved('updated A');
    Assert.AreEqual(0, Enumerator.Requests,
      'Saving A must not fetch B attachments or start rendering into B.');
  finally
    Launcher.Saved := nil;
    Host.Free;
    MarkdownEditorLauncher := PreviousLauncher;
    ElnFileEnumerator := PreviousEnumerator;
  end;
end;

procedure TMarkdownContextRegressions.HiddenToolbarRemainsHiddenAfterDeferredParenting;
var
  Host: TForm;
  Frame: TframeMarkdownViewer;
  I: Integer;
  Found: Boolean;
begin
  Host := TForm.CreateNew(nil);
  try
    Host.HandleNeeded;
    Frame := TframeMarkdownViewer.Create(Host);
    Frame.SetEditContext('C:\synthetic\preview.md', 10, 100);
    Frame.HideToolBar;
    Frame.Parent := Host;
    Found := False;
    for I := 0 to Frame.ComponentCount - 1 do
      if Frame.Components[I] is TRzToolbar then
      begin
        Found := True;
        Assert.IsFalse(TRzToolbar(Frame.Components[I]).Visible,
          'An embedded editor preview must not expose its own Edit toolbar.');
      end;
    Assert.IsTrue(Found);
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMarkdownContextRegressions);
end.
