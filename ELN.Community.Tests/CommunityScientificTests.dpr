program CommunityScientificTests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  test_ReportBuilder in 'test_ReportBuilder.pas',
  test_ItemDurability in 'test_ItemDurability.pas',
  test_ScientificIntegrity in 'test_ScientificIntegrity.pas',
  test_XRCProject in 'test_XRCProject.pas',
  unit_ELNPluginTypes in '..\ViewerPlugins\Core\unit_ELNPluginTypes.pas',
  unit_XRCProject in '..\ViewerPlugins\Viewer.XRayCalc\unit_XRCProject.pas',
  unit_XRCProjectOutput in '..\ViewerPlugins\Viewer.XRayCalc\unit_XRCProjectOutput.pas',
  unit_LayerSequence in '..\ViewerPlugins\Viewer.XRayCalc\unit_LayerSequence.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
begin
  try
    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    Runner.AddLogger(TDUnitXConsoleLogger.Create(True));
    Runner.FailsOnNoAsserts := True;
    Results := Runner.Execute;
    if not Results.AllPassed then System.ExitCode := 1;
  except
    on E: Exception do
    begin
      System.Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := 1;
    end;
  end;
end.
