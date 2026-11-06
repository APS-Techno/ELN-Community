unit test_MCPParamParsing;

interface

uses
  System.SysUtils, System.JSON,
  DUnitX.TestFramework,
  unit_LocalNotebook, unit_MCPTools, unit_Project;

type
  [TestFixture]
  TMCPParamParsingTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FProject: TProject;
    FArchived: TProject;
    function Run(const Tool, ParamsJson: string): TJSONObject;
    function ProjectCount(Response: TJSONObject): Integer;
    function AddProject(const Title: string; Archived: Boolean): TProject;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure GetOptBoolForms;
    [Test]
    procedure GetOptBoolRejectsGarbage;
    [Test]
    procedure GetOptNumericNullIsAbsent;
    [Test]
    procedure ListProjectsStringTrue;
    [Test]
    procedure ListProjectsStringFalse;
    [Test]
    procedure ListProjectsBoolTrue;
    [Test]
    procedure ListProjectsNull;
    [Test]
    procedure ListProjectsInvalidBool;
    [Test]
    procedure ListItemsNullOptionalIds;
    [Test]
    procedure QueryValuesNullOptionalIds;
  end;

implementation

uses
  System.IOUtils,
  Aurelius.Engine.ObjectManager,
  unit_ProjectModel, unit_ToolsWrite, unit_ToolsNavigation, unit_ToolsValues;

function TMCPParamParsingTests.AddProject(const Title: string;
  Archived: Boolean): TProject;
var
  Projects: TProjectsModel;
begin
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    Result := Projects.AddProject(Title, 'About ' + Title, FNotebook.Principal);
  finally
    Projects.Free;
  end;
  if Archived then
  begin
    Result.IsArchived := True;
    FNotebook.Manager.Flush;
  end;
end;

procedure TMCPParamParsingTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath,
    'ELN-MCPParam-' + TGUID.NewGuid.ToString);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Param fixture',
    'fixture-password');
  FProject := AddProject('Active', False);
  FArchived := AddProject('Archived', True);
end;

procedure TMCPParamParsingTests.TearDown;
begin
  FreeAndNil(FNotebook);
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TMCPParamParsingTests.Run(const Tool, ParamsJson: string): TJSONObject;
var
  Manager: TObjectManager;
  Context: TToolContext;
  Registry: TToolRegistry;
  Params: TJSONObject;
begin
  Params := TJSONObject.ParseJSONValue(ParamsJson) as TJSONObject;
  try
    Manager := TObjectManager.Create(FNotebook.Connection);
    try
      Context := Default(TToolContext);
      Context.Manager := Manager;
      Context.User := FNotebook.Principal;
      Context.AccessPolicy := FNotebook.AccessPolicy;
      Context.Storage := FNotebook.Storage;
      Registry := TToolRegistry.Create(Context);
      try
        RegisterNavigationTools(Registry);
        RegisterValueTools(Registry);
        Result := Registry.Execute(Tool, Params);
      finally
        Registry.Free;
      end;
    finally
      Manager.Free;
    end;
  finally
    Params.Free;
  end;
end;

function TMCPParamParsingTests.ProjectCount(Response: TJSONObject): Integer;
begin
  Result := Response.GetValue<TJSONArray>('projects').Count;
end;

procedure TMCPParamParsingTests.GetOptBoolForms;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.ParseJSONValue(
    '{"a":"True","b":" false ","c":"1","d":"0","e":true,"f":0,"g":2,' +
    '"h":null,"i":""}') as TJSONObject;
  try
    Assert.IsTrue(GetOptBool(Obj, 'a', False));
    Assert.IsFalse(GetOptBool(Obj, 'b', True));
    Assert.IsTrue(GetOptBool(Obj, 'c', False));
    Assert.IsFalse(GetOptBool(Obj, 'd', True));
    Assert.IsTrue(GetOptBool(Obj, 'e', False));
    Assert.IsFalse(GetOptBool(Obj, 'f', True));
    Assert.IsTrue(GetOptBool(Obj, 'g', False));
    Assert.IsTrue(GetOptBool(Obj, 'h', True));
    Assert.IsFalse(GetOptBool(Obj, 'h', False));
    Assert.IsTrue(GetOptBool(Obj, 'i', True));
    Assert.IsTrue(GetOptBool(Obj, 'missing', True));
    Assert.IsFalse(GetOptBool(nil, 'a', False));
  finally
    Obj.Free;
  end;
end;

procedure TMCPParamParsingTests.GetOptBoolRejectsGarbage;
var
  Obj: TJSONObject;
  Msg: string;
begin
  Obj := TJSONObject.ParseJSONValue('{"x":"not_a_bool"}') as TJSONObject;
  try
    Msg := '';
    try
      GetOptBool(Obj, 'x', False);
    except
      on E: Exception do
      begin
        Assert.AreEqual(Exception, E.ClassType);
        Msg := E.Message;
      end;
    end;
    Assert.AreEqual('Invalid boolean parameter "x": "not_a_bool" ' +
      '(expected true or false)', Msg);
  finally
    Obj.Free;
  end;
end;

procedure TMCPParamParsingTests.GetOptNumericNullIsAbsent;
var
  Obj: TJSONObject;
  I: Integer;
  I64: Int64;
  D: Double;
begin
  Obj := TJSONObject.ParseJSONValue(
    '{"a":null,"b":"null","c":" NULL ","d":5,"e":2.5}') as TJSONObject;
  try
    Assert.IsFalse(GetOptInt(Obj, 'a', I));
    Assert.IsFalse(GetOptInt(Obj, 'b', I));
    Assert.IsFalse(GetOptInt64(Obj, 'c', I64));
    Assert.IsFalse(GetOptNum(Obj, 'a', D));
    Assert.IsFalse(GetOptNum(Obj, 'b', D));
    Assert.IsTrue(GetOptInt(Obj, 'd', I));
    Assert.AreEqual(5, I);
    Assert.IsTrue(GetOptNum(Obj, 'e', D));
    Assert.AreEqual(2.5, D, 0.0001);
  finally
    Obj.Free;
  end;
end;

procedure TMCPParamParsingTests.ListProjectsStringTrue;
var
  R: TJSONObject;
begin
  R := Run('list_projects', '{"include_archived":"True"}');
  try
    Assert.AreEqual(2, ProjectCount(R));
  finally
    R.Free;
  end;
end;

procedure TMCPParamParsingTests.ListProjectsStringFalse;
var
  R: TJSONObject;
begin
  R := Run('list_projects', '{"include_archived":"false"}');
  try
    Assert.AreEqual(1, ProjectCount(R));
  finally
    R.Free;
  end;
end;

procedure TMCPParamParsingTests.ListProjectsBoolTrue;
var
  R: TJSONObject;
begin
  R := Run('list_projects', '{"include_archived":true}');
  try
    Assert.AreEqual(2, ProjectCount(R));
  finally
    R.Free;
  end;
end;

procedure TMCPParamParsingTests.ListProjectsNull;
var
  R: TJSONObject;
begin
  R := Run('list_projects', '{"include_archived":null}');
  try
    Assert.AreEqual(1, ProjectCount(R));
  finally
    R.Free;
  end;
end;

procedure TMCPParamParsingTests.ListProjectsInvalidBool;
var
  Msg: string;
  R: TJSONObject;
begin
  Msg := '';
  try
    R := Run('list_projects', '{"include_archived":"not_a_bool"}');
    R.Free;
  except
    on E: Exception do
      Msg := E.Message;
  end;
  Assert.AreEqual('Invalid boolean parameter "include_archived": ' +
    '"not_a_bool" (expected true or false)', Msg);
end;

procedure TMCPParamParsingTests.ListItemsNullOptionalIds;
var
  R: TJSONObject;
  Body: string;
begin
  Body := Format('{"project_id":%d,"folder_id":%%s}', [FProject.Id]);
  R := Run('list_items', Format(Body, ['null']));
  try
    Assert.IsNotNull(R.GetValue('items'));
  finally
    R.Free;
  end;
  R := Run('list_items', Format(Body, ['"null"']));
  try
    Assert.IsNotNull(R.GetValue('items'));
  finally
    R.Free;
  end;
end;

procedure TMCPParamParsingTests.QueryValuesNullOptionalIds;
var
  R: TJSONObject;
begin
  R := Run('query_values',
    '{"project_id":null,"limit":null,"value_type_id":"null"}');
  try
    Assert.IsNotNull(R);
  finally
    R.Free;
  end;
  R := Run('query_values', '{"project_id":"null","limit":"null"}');
  try
    Assert.IsNotNull(R);
  finally
    R.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMCPParamParsingTests);

end.
