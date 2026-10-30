unit test_ProjectTreeIdentity;

interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TProjectTreeIdentityTests = class
  public
    [Test] procedure OwnerSelectionKeepsLocalPrincipalAndVisibility;
  end;

implementation
uses System.SysUtils, System.IOUtils, System.Generics.Collections,
  unit_LocalNotebook, unit_DataModel, unit_ProjectTreeVM, unit_Project, unit_User;

procedure TProjectTreeIdentityTests.OwnerSelectionKeepsLocalPrincipalAndVisibility;
var
  Root: string;
  Notebook: TLocalNotebook;
  Data: TDataModel;
  VM: TProjectTreeVM;
  Foreign: TUser;
  OwnProject: TProject;
  Rows: TList<TProject>;
  PrincipalId: Integer;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'eln-tree-identity-' + TGUID.NewGuid.ToString);
  ForceDirectories(Root);
  try
    Notebook := TLocalNotebook.CreateNew(TPath.Combine(Root, 'notebook.sqlite'),
      TPath.Combine(Root, 'files'), 'Synthetic', 'Scientist', 'Synthetic-tree-only!');
    try
      Data := TDataModel.Create(Notebook.Connection, Notebook.Principal.Id,
        Notebook.AccessPolicy, Notebook.Storage);
      try
        PrincipalId := Data.User.Id;
        OwnProject := Data.Projects.AddProject('Visible local project', '', Data.User);
        Foreign := TUser.Create;
        Foreign.Username := 'foreign-owner';
        Foreign.FirstName := 'Synthetic';
        Foreign.LastName := 'Foreign';
        Foreign.Password := Data.User.Password;
        Foreign.Role := dbAdmin;
        Foreign.CreatedDate := Now;
        Data.Manager.Save(Foreign);
        Data.Manager.Flush;
        Data.Projects.AddProject('Hidden foreign project', '', Foreign);
        VM := TProjectTreeVM.Create(Data.Projects, Data.Folders, Data.Favorites,
          Data.Authors, Data.History, Data.Items, Data.ProjectGroups);
        try
          Rows := VM.GetProjects(Foreign.Id);
          try Assert.AreEqual<NativeInt>(0, Rows.Count, 'Selecting an owner must not grant its authority');
          finally Rows.Free; end;
          Assert.AreEqual(PrincipalId, Data.Projects.AssignedUserID);
          Assert.AreEqual(PrincipalId, Data.Authors.CurrentUser.Id);
          Rows := VM.GetProjects(PrincipalId);
          try
            Assert.AreEqual<NativeInt>(1, Rows.Count);
            Assert.AreEqual(OwnProject.Id, Rows[0].Id);
          finally Rows.Free; end;
          Assert.AreEqual(PrincipalId, Data.Projects.AssignedUserID);
        finally VM.Free; end;
      finally Data.Free; end;
    finally Notebook.Free; end;
  finally TDirectory.Delete(Root, True); end;
end;

initialization
  TDUnitX.RegisterTestFixture(TProjectTreeIdentityTests);
end.
