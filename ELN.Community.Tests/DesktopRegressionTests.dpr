program DesktopRegressionTests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  System.IOUtils,
  Vcl.Forms,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  unit_NotebookSettings,
  test_SharedDesktopMutations in 'test_SharedDesktopMutations.pas',
  test_SharedDesktopViewer in 'test_SharedDesktopViewer.pas',
  test_TemplateDialogLifetime in 'test_TemplateDialogLifetime.pas',
  test_ValueDialogValidation in 'test_ValueDialogValidation.pas',
  test_ValueSourceDesktop in 'test_ValueSourceDesktop.pas',
  test_FileIdentity in 'test_FileIdentity.pas',
  test_MCPFileDiscovery in 'test_MCPFileDiscovery.pas',
  test_ProjectTreeIdentity in 'test_ProjectTreeIdentity.pas',
  test_ViewerParsers in 'test_ViewerParsers.pas',
  test_ViewerValues in 'test_ViewerValues.pas',
  test_LAMMPSParser in 'test_LAMMPSParser.pas',
  test_XRCProject in 'test_XRCProject.pas',
  test_SharedViewerRegressions in '..\ViewerPlugins\Viewer.ColumnarData\test\test_SharedViewerRegressions.pas',
  test_ProtocolExtractionRegressions in '..\ViewerPlugins\Core.Protocol\test_ProtocolExtractionRegressions.pas',
  test_MarkdownContextRegressions in '..\ViewerPlugins\Viewer.Markdown\test\test_MarkdownContextRegressions.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
  SettingsRoot: string;
begin
  try
    SettingsRoot := TPath.Combine(TPath.GetTempPath,
      'ELN_DesktopRegression_' + TGUID.NewGuid.ToString);
    TDirectory.CreateDirectory(SettingsRoot);
    try
      TNotebookSettings.SetConfigFile(TPath.Combine(SettingsRoot, 'settings.ini'));
      Application.Initialize;
      TDUnitX.CheckCommandLine;
      Runner := TDUnitX.CreateRunner;
      Runner.AddLogger(TDUnitXConsoleLogger.Create(True));
      Runner.FailsOnNoAsserts := True;
      Results := Runner.Execute;
      if not Results.AllPassed then System.ExitCode := 1;
    finally
      TDirectory.Delete(SettingsRoot, True);
    end;
  except
    on E: Exception do
    begin
      System.Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := 1;
    end;
  end;
end.
