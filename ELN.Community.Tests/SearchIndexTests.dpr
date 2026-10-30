program SearchIndexTests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  unit_SearchPassages in '..\ELN.Search\unit_SearchPassages.pas',
  unit_PassageContext in '..\ELN.Search\unit_PassageContext.pas',
  unit_SearchDocumentProvider in '..\ELN.Model\unit_SearchDocumentProvider.pas',
  unit_SemanticSearchApi in '..\ELN.Search\unit_SemanticSearchApi.pas',
  unit_SemanticSearchFilter in '..\ELN.Model\unit_SemanticSearchFilter.pas',
  unit_SearchVisibility in '..\ELN.Model\unit_SearchVisibility.pas',
  unit_SearchIndexStore in '..\ELN.Search\unit_SearchIndexStore.pas',
  unit_SearchIndexer in '..\ELN.Search\unit_SearchIndexer.pas',
  unit_HybridSearch in '..\ELN.Search\unit_HybridSearch.pas',
  unit_SearchMetrics in '..\ELN.Search\unit_SearchMetrics.pas',
  unit_SemanticSearchService in '..\ELN.Search\unit_SemanticSearchService.pas',
  unit_LocalSemanticSearch in '..\ELN.Search\unit_LocalSemanticSearch.pas',
  unit_RemoteSemanticSearch in '..\ELN.Search\unit_RemoteSemanticSearch.pas',
  unit_CrossEncoder in '..\ELN.Search\unit_CrossEncoder.pas',
  unit_MainThreadSearchSource in '..\ELN.Desktop\Units\unit_MainThreadSearchSource.pas',
  unit_NativeLibrary in '..\ELN.Search\unit_NativeLibrary.pas',
  unit_SearchArtifacts in '..\ELN.Search\unit_SearchArtifacts.pas',
  unit_SearchArtifactInstall in '..\ELN.Search\unit_SearchArtifactInstall.pas',
  unit_TarGz in '..\ELN.Search\unit_TarGz.pas',
  unit_PdfiumApi in '..\ELN.Search\unit_PdfiumApi.pas',
  unit_TextExtractors in '..\ELN.Search\unit_TextExtractors.pas',
  unit_MarkupEntities in '..\ELN.Search\unit_MarkupEntities.pas',
  unit_TextStreamDecoder in '..\ELN.Search\unit_TextStreamDecoder.pas',
  unit_XmlTextScanner in '..\ELN.Search\unit_XmlTextScanner.pas',
  unit_OpenXmlPackage in '..\ELN.Search\unit_OpenXmlPackage.pas',
  unit_OfficeTextExtractors in '..\ELN.Search\unit_OfficeTextExtractors.pas',
  unit_MarkupTextExtractors in '..\ELN.Search\unit_MarkupTextExtractors.pas',
  unit_JsonTextExtractor in '..\ELN.Search\unit_JsonTextExtractor.pas',
  unit_RtfTextExtractor in '..\ELN.Search\unit_RtfTextExtractor.pas',
  unit_TextExtractorRegistry in '..\ELN.Search\unit_TextExtractorRegistry.pas',
  unit_FileTextStage in '..\ELN.Search\unit_FileTextStage.pas',
  unit_SearchTestSupport in 'unit_SearchTestSupport.pas',
  test_SearchArtifacts in 'test_SearchArtifacts.pas',
  test_SearchDoubles in 'test_SearchDoubles.pas',
  test_SearchStore in 'test_SearchStore.pas',
  test_PassageContextBuild in 'test_PassageContextBuild.pas',
{$IFDEF MSWINDOWS}
  test_SearchIndex in 'test_SearchIndex.pas',
  test_PassageContext in 'test_PassageContext.pas',
  test_SemanticSearchFilter in 'test_SemanticSearchFilter.pas',
{$ENDIF}
  test_TextExtractors in 'test_TextExtractors.pas',
  test_TextFormatExtractors in 'test_TextFormatExtractors.pas',
  test_SemanticSearchService in 'test_SemanticSearchService.pas',
  test_RemoteSemanticSearch in 'test_RemoteSemanticSearch.pas',
  test_SearchMetrics in 'test_SearchMetrics.pas';

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
