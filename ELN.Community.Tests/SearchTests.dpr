program SearchTests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  unit_NativeLibrary in '..\ELN.Search\unit_NativeLibrary.pas',
  unit_OnnxRuntimeApi in '..\ELN.Search\unit_OnnxRuntimeApi.pas',
  unit_UnigramTokenizer in '..\ELN.Search\unit_UnigramTokenizer.pas',
  unit_TextEmbedder in '..\ELN.Search\unit_TextEmbedder.pas',
  unit_VectorSearch in '..\ELN.Search\unit_VectorSearch.pas',
  unit_SearchArtifacts in '..\ELN.Search\unit_SearchArtifacts.pas',
  unit_CrossEncoder in '..\ELN.Search\unit_CrossEncoder.pas',
  unit_SearchTestSupport in 'unit_SearchTestSupport.pas',
  test_SearchEmbedding in 'test_SearchEmbedding.pas';

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
